# Стандарт готовности — Воркшоп 1

> Версия: v1.3 (2026-05-12). Добавлен **A.15 Tailscale/VPN — настоящая защита SSH** (SSH невидим в публичном интернете). A.11-A.14 остаются как минимум для тех кто оставляет SSH публичным.
> v1.2 (2026-05-12): A.11-A.14 SSH-hardening после брут-форс инцидента.
> Что должно быть настроено у участника после Воркшопа 1.
> Это **источник истины** — все промпты ссылаются на этот документ.
> AI и аудитор используют его как чек-лист.

---

## Легенда

- ❗ **Критично** — без этого спринт не пройден, нужно доделать
- ⚠️ **Рекомендуется** — лучше сделать, но не блокер
- 💡 **Опционально** — фича для продвинутых

---

## A. VPS базовая настройка

| # | Критерий | Уровень |
|---|---|---|
| A.1 | VPS работает на Ubuntu 24.04 LTS | ❗ |
| A.2 | Юзер `clawd` создан | ❗ |
| A.3 | Passwordless sudo для clawd: `ssh clawd@VPS "sudo -n whoami"` → `root` | ❗ |
| A.4 | Root SSH-логин заблокирован: `ssh root@VPS` → `Permission denied` | ❗ |
| A.5 | ufw active с rate-limit: `sudo ufw status` → `22/tcp LIMIT` | ❗ |
| A.6 | fail2ban active: `systemctl is-active fail2ban` → `active` | ❗ |
| A.7 | Swap 4GB: `swapon --show` показывает 4GB | ❗ |
| A.8 | Node.js v22.X через nvm под clawd: `node --version` → `v22.X` | ❗ |
| A.9 | Linger включён: `loginctl show-user clawd \| grep Linger` → `Linger=yes` | ❗ |
| A.10 | unattended-upgrades с Automatic-Reboot=false | ⚠️ |
| A.11 | SSH порт ≠ 22 (случайный 10000-60000): `grep ^Port /etc/ssh/sshd_config` → не 22. ufw разрешает только новый порт. | ❗ |
| A.12 | Password auth выключен: `grep PasswordAuthentication /etc/ssh/sshd_config` → `no`. Только ключи. | ❗ |
| A.13 | fail2ban bantime ≥ 86400 (24h), maxretry 3, findtime 600: `cat /etc/fail2ban/jail.local` или `sudo fail2ban-client get sshd bantime` → ≥86400 | ❗ |
| A.14 | `MaxStartups 5:30:10` и `MaxSessions 5` в sshd_config (защита от исчерпания connections под брут-форсом) | ⚠️ |
| A.15 | **SSH недоступен из публичного интернета** — VPN-туннель (Tailscale / WireGuard / Cloudflare Tunnel) ИЛИ IP-whitelist в ufw. Проверка: `nmap -p <SSH_PORT> <PUBLIC_IP>` с внешней машины → `filtered` или `closed`, не `open`. | ❗ |

⚠️ **Иерархия защит:**
- **A.15** — настоящая защита. SSH вообще не торчит в интернет — брут-форсить нечего. Рекомендуем **Tailscale** (5 мин установка, $0, кросс-платформенный Mac/Win/Linux/iOS/Android). Альтернативы: WireGuard (DIY), Cloudflare Tunnel (нужен домен), статичный IP whitelist в ufw.
- **A.11-A.14** — минимальный baseline для тех кто **отказывается** от VPN/туннеля. Это security-by-obscurity + key-auth + rate-limit. Защищает от 90% бот-трафика, **но не от целевой атаки**. Arch Wiki прямо говорит: «A port change... will reduce the number of log entries but will not eliminate them.»
- Контекст: в когорте Nov-2026 был зафиксирован 2-дневный брут-форс на порт 22, fail2ban с `bantime=3600` не справился — атакующие ротировали IP, забивали MaxStartups. После A.11-A.14 атака прекратилась за час. Но если бы стояло A.15 (Tailscale) — атаки бы не было вообще.

---

## B. OpenClaw daemon

| # | Критерий | Уровень |
|---|---|---|
| B.1 | OpenClaw установлен через npm под clawd (НЕ root): `which openclaw` показывает путь в `~/.npm-global/` или `~/.nvm/` | ❗ |
| B.2 | systemd-user сервис active: `systemctl --user status openclaw` → `active (running)` | ❗ |
| B.3 | Gateway на 127.0.0.1: `ss -tlnp \| grep 18789` → `127.0.0.1:18789` (НЕ `0.0.0.0`!) | ❗ |
| B.4 | doctor чистый: `openclaw doctor --deep` → 0 critical | ❗ |
| B.5 | Daemon переживает logout (linger проверен в A.9) | ❗ |
| B.6 | Auto-restart on failure включён в systemd unit | ⚠️ |

---

## C. Каскад моделей

| # | Критерий | Уровень |
|---|---|---|
| C.1 | 5 auth profiles: `openclaw auth list` показывает minimax, deepseek, openrouter, groq, openai | ❗ |
| C.2 | `missingProvidersInUse` пусто в `openclaw models status` | ❗ |
| C.3 | Primary: `minimax/MiniMax-M2.7` (⚠️ slug case-sensitive! С заглавными!) | ❗ |
| C.4 | Fallback на primary: `deepseek/deepseek-v4-flash` (ТОЛЬКО дешевле primary!) | ❗ |
| C.5 | Heartbeat: `openrouter/google/gemini-2.5-flash-lite`, every 60m, lightContext, isolatedSession | ⚠️ |
| C.6 | Subagents: `openrouter/moonshotai/kimi-k2.6` | ⚠️ |
| C.7 | Alias `premium`: `deepseek/deepseek-v4-pro` | ❗ |
| C.8 | Alias `think`: `deepseek/deepseek-v4-pro:thinking` | ⚠️ |
| C.9 | Probe primary зелёный (если поддерживается): `openclaw models status --probe` показывает minimax работает | ⚠️ |
| C.10 | В реальном ответе боту в Telegram модель = `minimax/MiniMax-M2.7` (НЕ deepseek!) — проверка через `openclaw logs --tail` | ❗ |

⚠️ **ВАЖНО про регистр slug-ов:** OpenClaw case-sensitive. Если probe возвращает 404 — первое что проверять это точный регистр: `MiniMax-M2.7`, не `minimax-m2.7`. Список доступных моделей: `openclaw models list --provider minimax` или `curl https://api.minimax.io/v1/models -H "Authorization: Bearer $KEY"`.

---

## D. Telegram-бот

| # | Критерий | Уровень |
|---|---|---|
| D.1 | Telegram channel active: `openclaw channels list` показывает telegram/main или telegram/default | ❗ |
| D.2 | dmPolicy: `allowlist` (НЕ `open`!) | ❗ |
| D.3 | allowFrom содержит ЧИСЛОВОЙ user_id (НЕ username — username меняется в один клик) | ❗ |
| D.4 | Token в файле `~/.openclaw/secrets/telegram.token` с правами `chmod 600` (НЕ в openclaw.json напрямую!) | ❗ |
| D.5 | Bot валиден: `curl https://api.telegram.org/bot$TOKEN/getMe` → `ok:true` | ❗ |
| D.6 | На «привет» в Telegram бот отвечает за ≤5 секунд | ❗ |
| D.7 | В ответе есть имя сотрудника из SOUL.md (например «я твой Кит») | ⚠️ |

---

## E. Картинки (image generation)

| # | Критерий | Уровень |
|---|---|---|
| E.1 | `tools.profile = "full"` (НЕ `messaging` и НЕ `coding`!) | ❗ |
| E.2 | Image default: `openrouter/google/gemini-2.5-flash-image` | ⚠️ |
| E.3 | Image fast: `openrouter/black-forest-labs/flux-schnell` | ⚠️ |
| E.4 | На `/image кот` в Telegram приходит картинка за 5-15 секунд | ⚠️ |
| E.5 | Стоимость одной картинки ≤ $0.05 (`openclaw spend --since="-5m"`) | ⚠️ |

---

## F. Защита от runaway

| # | Критерий | Уровень |
|---|---|---|
| F.1 | Watchdog cron установлен: `crontab -l` содержит `*/30 * * * * .../watchdog.sh` | ❗ |
| F.2 | Watchdog скрипт существует: `~/.openclaw/scripts/watchdog.sh` с правами `+x` | ❗ |
| F.3 | В watchdog.sh реальные TG_TOKEN и TG_USER_ID (не пустые, не `${VAR}`) | ❗ |
| F.4 | Watchdog тест: `bash ~/.openclaw/scripts/watchdog.sh; echo $?` → `0` (spend=0, ничего не сделает) | ⚠️ |
| F.5 | OpenRouter Spending Limit $30/мес выставлен (проверяется вручную в браузере) | ❗ |
| F.6 | Config-level spending caps в openclaw.json (если поддерживается схемой) | 💡 |
| F.7 | premiumGuard в openclaw.json (если поддерживается схемой) | 💡 |

⚠️ **Известное ограничение OpenClaw 2026.4.27:** `spending` и `premiumGuard` секции в схеме НЕ применяются. Полагаемся на watchdog (F.1-F.4) + provider limit (F.5).

---

## G. Голосовые сообщения

| # | Критерий | Уровень |
|---|---|---|
| G.1 | TTS настроен: `messages.tts.provider = openai`, `model = tts-1`, `voice = alloy`, `maxTextLength = 200` | ⚠️ |
| G.2 | На короткое текстовое сообщение бот отвечает голосом | ⚠️ |
| G.3 | Whisper транскрипция входящих голосовых работает (если найден способ настройки в 2026.4.27) | 💡 |

⚠️ **Известное ограничение OpenClaw 2026.4.27:** `voice.transcription` секция в схеме другая. Whisper Groq для входящих — отложено до Воркшопа 2 / решения от мейнтейнеров.

---

## H. UX и чистота

| # | Критерий | Уровень |
|---|---|---|
| H.1 | Бот не показывает в Telegram технические `Working...`/`sessions_yield` (см. setting `messages.progress` если есть) | ⚠️ |
| H.2 | Бот не показывает chain-of-thought, function calls, JSON-теги в ответах | ⚠️ |
| H.3 | SOUL.md содержит anti-sycophancy правило (без «Отличный вопрос!») | ⚠️ |

---

## Финальный итог

После Воркшопа 1 **минимум** должен быть закрыт каждый ❗ критерий.
⚠️ — желательно закрыть к Воркшопу 2, не блокирует.
💡 — фичи будущего, post-sprint материал.

**Зачёт В1:** все ❗ закрыты И бот в Telegram отвечает на «привет» используя MiniMax (не fallback).

---

## Что ОТКЛЮЧЕНО в схеме OpenClaw 2026.4.27

Известные несостыковки между нашим deck-шаблоном и реальной схемой текущей версии. Не считать ошибкой:

- ❌ `auth.profiles` в openclaw.json — заменено на CLI `openclaw auth set`
- ❌ `voice.transcription` — схема другая, Whisper отложен
- ❌ `spending` config caps — не применяется, полагаемся на watchdog
- ❌ `premiumGuard.expireAfterMessages` — не применяется, fallback в SOUL.md правило
- ❌ `heartbeat.rateLimit` / `skipWhenBusy` / `fallbacks` — не поддерживается
- ❌ `mcp` секция — настраивается отдельно через CLI (Воркшоп 3)

Эти секции в нашем `config/openclaw.json` молча игнорируются OpenClaw — это OK для этой версии.
