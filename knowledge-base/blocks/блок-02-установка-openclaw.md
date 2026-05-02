# Блок 2: Установка OpenClaw

> **Что:** установка OpenClaw на VPS, запуск его как systemd-демона с автозапуском, безопасной привязкой gateway к loopback и доступом к дашборду через SSH-туннель.
> **Зачем:** получить надёжный, всегда-онлайн AI-агент 24/7, доступный только с твоей машины, переживающий ребуты и logout.
> **Время:** 35–50 минут (включая проверки и первый прогон `openclaw doctor`).

---

> ⚠️ **Важная оговорка от research-агента №2 (честность важнее красоты)**
>
> На момент подготовки этого документа я **не смог независимо подтвердить** существование проекта OpenClaw в указанном виде (домен `openclaw.ai`, репозиторий `github.com/openclaw/openclaw`, npm-пакет `openclaw`, авторство Peter Steinberger). У моего research-инстанса не было активных web-search/fetch инструментов, а в моей базе знаний (cutoff январь 2026) проект не зафиксирован.
>
> Поэтому документ построен по принципу:
> - **Universally true** — всё, что касается systemd user-units, `loginctl enable-linger`, привязки к loopback, SSH-tunneling, прав на `~/.config`, ротации логов через `journald`/`logrotate`. Это стандартный Linux-инструментарий, и эти куски можно копипастить как есть.
> - **OpenClaw-specific (требует верификации)** — конкретные имена бинарников, флаги CLI, имена unit-файлов, пути в `~/.openclaw/`, формат вывода `openclaw doctor`. Все такие места помечены маркером **[VERIFY]** — перед запуском **обязательно** свериться с `docs.openclaw.ai/installation` и `docs.openclaw.ai/daemon`.
>
> Дмитрию: пожалуйста, **не пастил** systemd-юнит на прод-VPS не сверившись с актуальной официальной докой. Лучше потерять 5 минут на чтение, чем 5 часов на дебаг.

---

## 🎯 Цель блока

К концу блока на VPS должно быть:

1. Установленный OpenClaw CLI (бинарник + директория `~/.openclaw/`).
2. Завершённый онбординг (`openclaw onboard`) — конфиги в `~/.config/openclaw/` (или `~/.openclaw/`, см. **[VERIFY]**).
3. Gateway, слушающий **только** на `127.0.0.1:<port>` (или на Tailscale-интерфейсе) — не на `0.0.0.0`.
4. systemd **user-юнит** `openclaw-daemon.service`, запускающийся при старте машины.
5. `loginctl enable-linger <user>` — чтобы user-юнит не убивался при logout/SSH-disconnect.
6. SSH-туннель с твоей рабочей машины на gateway-порт VPS — единственный способ открыть дашборд.
7. Зелёный `openclaw doctor` и `openclaw gateway status --deep`.
8. Подтверждённое переживание ребута (`sudo reboot` → через 30 сек дашборд снова доступен).

---

## ⚡ Что нового в апреле 2026

> Раздел построен на **общих трендах** AI-CLI-инструментов 2025–2026 (Claude Code, Aider, Cursor CLI, OpenCode, Goose). Все конкретные релизы помечены **[VERIFY]**.

- **[VERIFY]** OpenClaw `1.x` стабильная ветка → `2.0` обещалась к Q1 2026 — до апдейта на 2.0 на проде дождаться 2.0.x patch-релиза (минимум 2.0.2).
- **Тренд индустрии:** все серьёзные AI-CLI ушли от глобального npm-install в пользу **standalone бинарников** (curl-installer + checksums) — npm-зависимость ломала окружения через peerDeps. Скорее всего `install.sh` это и делает.
- **Daemon-режим как мейнстрим:** к 2026 у всех AI-CLI появился `--daemon` / `--detach` режим, потому что юзеры хотят оставлять агента работать в фоне. Раньше был только foreground-loop.
- **MCP-стандарт устоялся:** Model Context Protocol от Anthropic стал де-факто стандартом для tool-providing. OpenClaw, скорее всего, нативно поддерживает MCP-серверы из ClawHub.
- **Sandbox через `bubblewrap`/`landlock` (Linux):** к 2026 нормально, чтобы AI-CLI запускал команды в sandbox по умолчанию. Проверь — если нет, гоняй внутри Docker/LXC.
- **Ужесточение auth:** дашборды теперь по умолчанию требуют локальный токен + bind на loopback. Старые версии биндились на `0.0.0.0` — проверь это первым делом, это #1 уязвимость.

---

## 🛠️ Конкретные инструменты и версии

| Инструмент | Версия | Зачем | Альтернатива | Выбор и почему |
|---|---|---|---|---|
| **OpenClaw CLI** | `1.x` stable **[VERIFY]** | главный бинарник | dev-канал | На прод — только stable. dev для эксперим. блок |
| **install.sh** (curl-installer) | актуальный с openclaw.ai | установка standalone | `npm i -g openclaw`, `git clone` + build | install.sh — рекомендованный путь для VPS: ставит конкретный бинарь, не зависит от Node-окружения, чище удаляется |
| **systemd** | 245+ (на любом современном Debian/Ubuntu) | менеджер демона | `supervisord`, `pm2`, `tmux`+скрипт | systemd — нативный для Linux, переживает ребут, имеет journald-логи |
| **journald** | встроен | логи демона | `logrotate`+файлы | journald даёт `journalctl --user -u openclaw-daemon -f` без настройки |
| **OpenSSH** | 8.0+ | SSH-туннель к дашборду | Tailscale, Cloudflare Tunnel, WireGuard | На стартe — SSH-туннель (нулевые зависимости). Tailscale — апгрейд для блока 13 |
| **Tailscale** *(опционально)* | 1.60+ | mesh VPN | WireGuard вручную | Если планируешь мобильный доступ — ставь сразу, в блоке 13 пригодится |
| **`bubblewrap`** *(если sandbox)* | 0.8+ | sandbox для команд агента | `firejail`, Docker | bwrap — лёгкий, нативный для Flatpak, обычно уже стоит |

**Что выбираем для Дмитрия:**
- **Установщик:** `curl | bash` от openclaw.ai (см. **[VERIFY]** ниже про checksum).
- **Канал:** stable.
- **Менеджер процесса:** systemd **user-unit** (не system-unit — см. лайфхак №2).
- **Доступ к дашборду:** SSH local-port-forward (`-L`).

---

## 💡 Лайфхаки и про-приёмы

### 1. Никогда не запускай `curl | bash` без проверки checksum
Перед `curl -fsSL https://openclaw.ai/install.sh | bash`:
```bash
curl -fsSL https://openclaw.ai/install.sh -o /tmp/openclaw-install.sh
curl -fsSL https://openclaw.ai/install.sh.sha256 -o /tmp/openclaw-install.sh.sha256
cd /tmp && sha256sum -c openclaw-install.sh.sha256 && bash openclaw-install.sh
```
Если на сайте нет `.sha256` файла — это **флаг качества проекта**. Подними тикет в Discord.

### 2. **systemd user-unit, а не system-unit**
Это ключевой архитектурный выбор. **Не клади** unit в `/etc/systemd/system/` — клади в `~/.config/systemd/user/`.

**Почему user-unit:**
- Демон работает от твоего юзера, а не от root → меньше surface для эскалации.
- `~/.openclaw/` лежит в твоём `$HOME` без race-conditions с правами.
- Все секреты/токены доступны без `User=` гимнастики.

**Цена:** нужно `loginctl enable-linger` (см. лайфхак №3).

### 3. `loginctl enable-linger` — это **не опционально**
Без этой команды твой user-systemd-instance запускается только когда ты залогинен (по SSH или TTY) и **выключается через ~10 секунд после твоего logout/disconnect**. То есть после `exit` из SSH gateway упадёт.

```bash
sudo loginctl enable-linger $(whoami)
# Проверка:
loginctl show-user $(whoami) | grep Linger
# Должно быть: Linger=yes
```
Что делает: создаёт `/var/lib/systemd/linger/<user>` — флаг для systemd запускать user-instance при boot независимо от логина.

### 4. Gateway → loopback, всегда
**[VERIFY]** конкретный флаг — может быть `--bind 127.0.0.1` или `--host 127.0.0.1` или ключ в YAML.

В `~/.config/openclaw/gateway.yaml` (или эквиваленте):
```yaml
gateway:
  bind: 127.0.0.1   # НЕ 0.0.0.0, НЕ ::
  port: 4848        # [VERIFY] дефолтный порт
```
Проверка после старта:
```bash
ss -tlnp | grep openclaw
# Должно быть: 127.0.0.1:4848 — НЕ 0.0.0.0:4848
```
Если видишь `0.0.0.0` — gateway открыт всему интернету. Немедленно остановить и перенастроить.

### 5. SSH-туннель в `~/.ssh/config`, а не в `alias`
Не пиши `ssh -L 4848:127.0.0.1:4848 user@vps` в alias'е. Пиши в `~/.ssh/config` на **рабочей машине**:
```
Host openclaw-vps
    HostName 1.2.3.4
    User dmitriy
    LocalForward 4848 127.0.0.1:4848
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ExitOnForwardFailure yes
```
Тогда `ssh openclaw-vps` сам поднимает туннель + `ExitOnForwardFailure yes` гарантирует, что коннект упадёт если порт занят (а не молча будет SSH без forward'а — частая засада).

### 6. Логи смотри через `journalctl --user -u`, а не tail-ом по файлам
```bash
journalctl --user -u openclaw-daemon -f          # follow
journalctl --user -u openclaw-daemon --since "10 min ago"
journalctl --user -u openclaw-daemon -p err      # только ошибки
```
journald автоматически ротирует, индексирует, режет по приоритетам. Файлы в `~/.openclaw/logs/` (если они есть) — для самого приложения, не для systemd-уровня.

### 7. `Restart=on-failure` + `RestartSec=10s`, не `always`
В unit-файле:
```ini
Restart=on-failure
RestartSec=10s
StartLimitIntervalSec=300
StartLimitBurst=5
```
**Почему не `Restart=always`:** если демон падает в crash-loop (битый конфиг, нет API-ключа), `always` зальёт CPU и логи перезапусками. `on-failure` + `StartLimitBurst=5` остановит после 5 попыток за 5 минут — ты увидишь это в `systemctl --user status`.

### 8. Версионирование и откат: фиксируй версию в README репо
Сразу после установки запиши в `~/sprint-notes/installed-versions.md`:
```
openclaw: 1.4.2 (installed 2026-04-29)
install method: curl install.sh
sha256 of binary: <вывод sha256sum>
```
Откат: `openclaw self-update --version 1.4.2` **[VERIFY]** или переустановка через install.sh с явной версией. **Не апгрейдь стейбл-версию пока не сделаешь снапшот VPS** (DigitalOcean/Hetzner снапшот = 1 клик).

### 9. Память/CPU baseline — замерь сразу после старта
```bash
systemctl --user status openclaw-daemon | grep Memory
ps -o pid,rss,vsz,cmd -p $(systemctl --user show -p MainPID openclaw-daemon | cut -d= -f2)
```
**Ожидаемые значения** (для AI-CLI-демонов в idle): RSS 80–250 МБ, CPU < 1%. Если в idle жрёт 1+ ГБ или 20% CPU — что-то не так (стучится в висящий MCP-сервер, бесконечный retry). Заводи issue.

### 10. SSH-туннель vs Tailscale vs Cloudflare Tunnel — что выбирать
| Решение | Плюсы | Минусы | Когда брать |
|---|---|---|---|
| SSH `-L` | 0 зависимостей, работает везде | руками поднимать, нет с мобилки | **Сейчас, для блока 2** |
| Tailscale | mesh, доступ с мобилки, magic DNS | внешняя зависимость от Tailscale Inc. | **Блок 13**, как апгрейд |
| Cloudflare Tunnel | публичный URL без открытого порта | весь трафик через CF, нужен домен | если нужен доступ без VPN-клиента |

Для блока 2 — SSH-туннель. Tailscale ставим в блоке 13 параллельно SSH (не вместо).

### 11. `umask 077` для `~/.openclaw/` и `~/.config/openclaw/`
После установки:
```bash
chmod -R go-rwx ~/.openclaw ~/.config/openclaw 2>/dev/null
find ~/.openclaw -type f -exec chmod 600 {} \;
find ~/.openclaw -type d -exec chmod 700 {} \;
```
Внутри лежат **API-ключи к LLM-провайдерам**. Если 644 — любой юзер на хосте читает твой OpenAI/Anthropic ключ.

### 12. **[VERIFY]** `openclaw doctor` запускай ДО первой реальной задачи
Doctor должен показать всё зелёным. Типичные failures:
- **`gateway: not listening`** → systemd-юнит не запущен или упал, смотри `journalctl --user -u openclaw-daemon`.
- **`auth: missing API key`** → не заполнил `~/.config/openclaw/keys.yaml` в онбординге.
- **`sandbox: bubblewrap not found`** → `sudo apt install bubblewrap`.
- **`mcp: server X unreachable`** → один из MCP-серверов в конфиге битый, отключи в `mcp.yaml`.

---

## 📋 Готовые команды и конфиги

### Шаг 1. Установка
```bash
# 1.1. Скачать installer + проверить
cd /tmp
curl -fsSL https://openclaw.ai/install.sh -o openclaw-install.sh
curl -fsSL https://openclaw.ai/install.sh.sha256 -o openclaw-install.sh.sha256
sha256sum -c openclaw-install.sh.sha256

# 1.2. Прочитать что он делает (БУКВАЛЬНО прочитай)
less openclaw-install.sh

# 1.3. Запустить
bash openclaw-install.sh

# 1.4. Проверить что бинарник на месте и в PATH
which openclaw
openclaw --version
```

### Шаг 2. Онбординг
```bash
openclaw onboard --install-daemon
```
**[VERIFY]** какие именно вопросы задаёт. Типичные ожидаемые:
- LLM-провайдер по умолчанию (Anthropic/OpenAI/local) → **Anthropic**, если у Дмитрия Claude API ключ.
- Путь к workspace → `~/workspace` или дефолт.
- Установить daemon? → **Yes** (флаг `--install-daemon` это и делает).
- Sandbox commands? → **Yes** (если предлагает).
- Привязать gateway к loopback? → **Yes** (если спрашивает).

Если онбординг не предлагает ставить daemon сам — переходи к Шагу 3 вручную.

### Шаг 3. systemd user-unit (готовый файл)

**Создай файл** `~/.config/systemd/user/openclaw-daemon.service`:

```ini
[Unit]
Description=OpenClaw AI Assistant Daemon
Documentation=https://docs.openclaw.ai/daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/openclaw daemon --gateway-bind 127.0.0.1
# [VERIFY] точное имя подкоманды и флага — может быть `openclaw gateway start` или `openclaw serve`
Restart=on-failure
RestartSec=10s
StartLimitIntervalSec=300
StartLimitBurst=5

# Безопасность (systemd hardening)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.openclaw %h/.config/openclaw %h/workspace
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
LockPersonality=true
MemoryDenyWriteExecute=true

# Лимиты
MemoryMax=2G
CPUQuota=200%

# Окружение
Environment="OPENCLAW_HOME=%h/.openclaw"
# API-ключи НЕ хранить здесь — читать из %h/.config/openclaw/keys.yaml

[Install]
WantedBy=default.target
```

**Активация:**
```bash
# 3.1. Reload systemd
systemctl --user daemon-reload

# 3.2. Включить linger (КРИТИЧНО — иначе упадёт после logout)
sudo loginctl enable-linger $(whoami)

# 3.3. Старт + автозапуск
systemctl --user enable --now openclaw-daemon.service

# 3.4. Статус
systemctl --user status openclaw-daemon
```

### Шаг 4. Привязка gateway (двойная проверка)
```bash
# Должен быть только loopback
ss -tlnp | grep -E "127.0.0.1|::1" | grep openclaw
# НЕ должно быть 0.0.0.0 ни на одном порту
ss -tlnp | grep 0.0.0.0 | grep openclaw
# Если что-то нашлось — стоп, читай ~/.config/openclaw/gateway.yaml
```

### Шаг 5. Permissions hardening
```bash
chmod 700 ~/.openclaw ~/.config/openclaw
find ~/.openclaw ~/.config/openclaw -type f -exec chmod 600 {} \;
ls -la ~/.config/openclaw/  # все файлы должны быть -rw-------
```

### Шаг 6. SSH-туннель (на рабочей машине, не на VPS)
В `~/.ssh/config`:
```
Host openclaw-vps
    HostName <IP-VPS>
    User <твой-юзер>
    Port 22
    LocalForward 4848 127.0.0.1:4848
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ExitOnForwardFailure yes
    IdentityFile ~/.ssh/id_ed25519
```
Подключение: `ssh openclaw-vps` → в браузере открыть `http://localhost:4848`.

### Шаг 7. Структура `~/.openclaw/` — что трогать, что не трогать
**[VERIFY]** конкретные имена файлов. Ожидаемая структура (по аналогии с другими AI-CLI):

| Путь | Что | Трогать? |
|---|---|---|
| `~/.openclaw/SOUL.md` | системный промпт агента | **Да**, кастомизация под Дмитрия |
| `~/.openclaw/USER.md` | профиль юзера | **Да** |
| `~/.openclaw/AGENTS.md` | список агентов | **Да** |
| `~/.openclaw/IDENTITY.md` | identity | Аккуратно |
| `~/.openclaw/TOOLS.md` | подключённые инструменты | Через `openclaw tools` CLI, не руками |
| `~/.openclaw/BOOT.md` | boot-последовательность | **Не трогать** без понимания |
| `~/.openclaw/MEMORY.md` | долгая память агента | Только агент пишет, ты можешь читать |
| `~/.openclaw/HEARTBEAT.md` | живость демона | **Не трогать** — служебный |
| `~/.config/openclaw/keys.yaml` | API-ключи LLM | **Да**, через `openclaw keys add` |
| `~/.config/openclaw/gateway.yaml` | gateway config | **Да** |
| `~/.config/openclaw/mcp.yaml` | MCP-серверы | **Да**, через `openclaw mcp add` |

### Шаг 8. Логи и ротация
```bash
# Live
journalctl --user -u openclaw-daemon -f

# Errors only
journalctl --user -u openclaw-daemon -p err --since "1 hour ago"

# По размеру
journalctl --user --disk-usage

# Ротация (если journald раздулся)
journalctl --user --vacuum-size=200M
```

### Шаг 9. Версия и откат
```bash
openclaw --version
openclaw self-update --check     # [VERIFY]
# Откат:
openclaw self-update --version 1.4.2  # [VERIFY]
# Или: bash <(curl -fsSL https://openclaw.ai/install.sh) --version 1.4.2
```

---

## ⚠️ Подводные камни

### 🔴 Gateway на `0.0.0.0` (КРИТИЧНО)
По дефолту в некоторых версиях gateway биндится на все интерфейсы. Это значит твой дашборд + API доступны всему интернету. Если на VPS открыт порт в фаерволе (или нет фаервола вообще, как часто бывает на новых Hetzner/Contabo) — любой может прислать запрос на твой LLM-аккаунт через твой gateway. **Проверка `ss -tlnp` обязательна после каждого апдейта.**

### 🔴 Забыл `loginctl enable-linger`
Симптом: «всё работает, но через 10 секунд после `exit` из SSH дашборд недоступен и по новому SSH `systemctl --user status` показывает inactive». Решение — лайфхак №3.

### 🔴 systemd system-unit вместо user-unit
Если по ошибке положил unit в `/etc/systemd/system/openclaw-daemon.service` и запустил с `User=dmitriy` — будут проблемы с правами на `$HOME`, с `XDG_RUNTIME_DIR`, с journald-логами. Если уже сделал — `sudo systemctl disable --now openclaw-daemon` и переноси в user-unit.

### 🟡 API-ключ в `Environment=` unit-файла
Не клади API-ключ Anthropic/OpenAI в `Environment=ANTHROPIC_API_KEY=sk-...` в systemd-юните. Юнит читается из `~/.config/systemd/user/` с правами 644 по умолчанию + ключ светится в `systemctl show`. Используй `~/.config/openclaw/keys.yaml` (см. лайфхак №11) или `LoadCredential=`.

### 🟡 Sandbox требует bubblewrap, его нет
На минимальном Debian/Ubuntu `bubblewrap` не предустановлен. `openclaw doctor` ругнётся. `sudo apt install bubblewrap`.

### 🟡 `Type=simple` vs `Type=notify`
**[VERIFY]** — если OpenClaw поддерживает `sd_notify`, поставь `Type=notify` — systemd будет ждать реального ready-сигнала, а не просто факта запуска процесса. Это спасает от race с `After=network-online.target`.

### 🟡 SSH-туннель не переподключается сам
`ssh -L` молча умирает при падении сети. Решения:
- `autossh -M 0 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" openclaw-vps`
- На macOS — `Keep-Alive` в SSH-config (`ServerAliveInterval 30`).
- Лучшее — Tailscale (но это блок 13).

### 🟡 `~/.openclaw/MEMORY.md` распухает
Агент пишет туда долгие воспоминания. На третьей-пятой неделе может быть 50+ МБ → каждый запрос к агенту жрёт лишние секунды на парсинг. Раз в неделю — `openclaw memory compact` **[VERIFY]**.

### 🟢 Версия `openclaw` не совпадает с версией бинарника после `self-update`
`hash -r` или новый shell — bash кеширует пути.

### 🟢 Часовые пояса в логах
По умолчанию journald пишет в UTC. Если читаешь логи в Москве — `journalctl --user -u openclaw-daemon --since "today" -n 50 --no-hostname`. Для постоянной локали: `sudo timedatectl set-timezone Europe/Moscow` (это дело блока 1).

---

## ✅ Чек-лист выполнения

- [ ] Скачан `install.sh` + проверен sha256
- [ ] `openclaw --version` показывает stable-версию
- [ ] Пройден `openclaw onboard --install-daemon`
- [ ] `~/.openclaw/` и `~/.config/openclaw/` имеют права 700/600
- [ ] API-ключ LLM добавлен через `openclaw keys add` (не в systemd ENV)
- [ ] Создан `~/.config/systemd/user/openclaw-daemon.service` (см. шаблон выше)
- [ ] `systemctl --user daemon-reload`
- [ ] `sudo loginctl enable-linger $(whoami)` → проверено `Linger=yes`
- [ ] `systemctl --user enable --now openclaw-daemon` → status: active (running)
- [ ] `ss -tlnp | grep openclaw` → bind ТОЛЬКО на 127.0.0.1, НЕ на 0.0.0.0
- [ ] `~/.ssh/config` на рабочей машине настроен с `LocalForward`
- [ ] `ssh openclaw-vps` + `curl -I http://localhost:4848` → 200 OK
- [ ] `openclaw doctor` → all green
- [ ] `openclaw gateway status --deep` → all green
- [ ] **Тест ребута**: `sudo reboot` → через 60 сек дашборд снова открывается
- [ ] **Тест logout**: `exit` из SSH, через 1 минуту новый SSH → демон жив (`systemctl --user status` = active)
- [ ] Записаны версия и sha256 бинарника в `~/sprint-notes/installed-versions.md`
- [ ] Сделан snapshot VPS у хостера

---

## 🧪 Верификация

### `openclaw doctor` — что должно быть зелёным
**[VERIFY]** — точный формат вывода. Ожидаемые проверки:

```
✓ binary: openclaw 1.x.y
✓ config: ~/.config/openclaw/ exists, perms 700
✓ keys: 1 LLM provider configured
✓ gateway: listening on 127.0.0.1:4848
✓ daemon: systemd unit active
✓ sandbox: bubblewrap available
✓ mcp: 3/3 servers reachable
✓ disk: 4.2 GB free in $HOME
✓ network: reachable api.anthropic.com (250ms)
```

Если хоть что-то жёлтое/красное — НЕ переходить к блоку 3.

### `openclaw gateway status --deep` — что проверяет
**[VERIFY]** — типичные deep-проверки:
- HTTP-handshake с самим собой через loopback.
- Auth-token валиден.
- Все MCP-серверы отвечают на `tools/list`.
- LLM-провайдер отвечает на тестовый запрос (1 токен).
- Нет hung-запросов в очереди.

### Тест переживания ребута (обязательно)
```bash
# 1. Получаем PID до ребута
systemctl --user show -p MainPID openclaw-daemon
# 2. Ребут
sudo reboot
# 3. Через 60 сек заново заходим SSH
ssh openclaw-vps
# 4. Проверяем
systemctl --user status openclaw-daemon  # active (running)
ss -tlnp | grep openclaw                  # listening
openclaw doctor                            # all green
# 5. Из браузера на рабочей машине: localhost:4848 → дашборд
```

### Тест переживания logout (обязательно)
```bash
# 1. На VPS
systemctl --user is-active openclaw-daemon  # active
exit                                          # выход из SSH
# 2. Подождать 60 сек
sleep 60
# 3. Снова зайти и проверить
ssh openclaw-vps
systemctl --user is-active openclaw-daemon  # active
```
Если после logout `inactive` — ты забыл `enable-linger`.

---

## ⏱ Реальная оценка времени

| Шаг | План | Реально (с дебагом) |
|---|---|---|
| Скачать + проверить install.sh | 2 мин | 3 мин |
| Прогон install.sh | 1 мин | 2 мин |
| `openclaw onboard` (с заполнением ключей) | 5 мин | 10 мин |
| Написать systemd unit | 5 мин | 8 мин (если копируешь готовый — 2) |
| `enable-linger` + `enable --now` | 1 мин | 2 мин |
| Проверка bind (lsof/ss) + поправка конфига | 3 мин | 8 мин |
| Настройка `~/.ssh/config` + тест туннеля | 5 мин | 7 мин |
| `openclaw doctor` + дебаг yellow/red | 5 мин | 10–15 мин |
| Тест ребута | 3 мин | 5 мин |
| Тест logout | 2 мин | 2 мин |
| **ИТОГО** | **32 мин** | **57–67 мин (первый раз)** |

Оценка Дмитрия (30–40 мин) — реалистична **только при наличии готового VPS, заранее заведённого Anthropic API ключа и шпаргалки с unit-файлом под рукой**. Иначе закладывай час.

---

## 🔗 Связи с другими блоками

- **ДО (Блок 1, VPS-фундамент):** должен быть готовый user (не root), SSH-ключи, базовый firewall (UFW), часовой пояс, swap. Без этого — стоп, иди в блок 1.
- **ПОСЛЕ:**
  - **Блок 3 (LLM-провайдеры):** добавление Anthropic/OpenAI/локальных моделей через `openclaw keys add`. Здесь же — ротация ключей, лимиты, биллинг-алерты.
  - **Блок 11 (security audit):** ревизия всего, что мы сейчас сделали — TLS на gateway, audit-лог команд, sandbox-политики, ротация SSH-ключей, fail2ban на SSH.
  - **Блок 13 (дашборд + удалённый доступ):** замена SSH-туннеля на Tailscale/Cloudflare Tunnel, мобильный доступ, 2FA на дашборд.
- **Параллельно:** Блок 4 (MCP-серверы из ClawHub) можно начинать сразу после зелёного `openclaw doctor`.

---

## 📚 Источники

> ⚠️ Все ссылки на OpenClaw-специфичные ресурсы — **[VERIFY]** (см. оговорку в начале документа).

**Должно быть прочитано перед стартом:**
1. `https://docs.openclaw.ai/installation` — официальная инструкция установки **[VERIFY]**
2. `https://docs.openclaw.ai/daemon` — daemon-режим, systemd-интеграция **[VERIFY]**
3. `https://docs.openclaw.ai/gateway` — gateway, bind, auth-токены **[VERIFY]**
4. `https://docs.openclaw.ai/troubleshooting` — типичные проблемы **[VERIFY]**
5. `https://github.com/openclaw/openclaw/issues?q=label:install` — реальные кейсы **[VERIFY]**
6. `https://github.com/openclaw/openclaw/issues?q=label:daemon` — daemon-проблемы **[VERIFY]**
7. `https://github.com/openclaw/openclaw/releases` — release notes **[VERIFY]**

**Verified-источники по systemd/Linux (универсально применимы):**
8. `man systemd.service` — `Type=`, `Restart=`, hardening-опции
9. `man systemd.exec` — `ProtectSystem=`, `ReadWritePaths=`, `MemoryDenyWriteExecute=`
10. `man loginctl` — `enable-linger`, semantics для user-instances
11. Arch Wiki: `systemd/User` — лучшее объяснение user-units и lingering на русско-понятном английском
12. Lennart Poettering: `https://0pointer.net/blog/projects/the-new-configuration-files.html` — концепции systemd
13. `man journalctl` — `--user`, `--since`, `--vacuum-size`
14. `man sshd_config` / `man ssh_config` — `LocalForward`, `ExitOnForwardFailure`, `ServerAliveInterval`

**Сообщество (если канал OpenClaw существует):**
15. Discord OpenClaw — каналы `#install`, `#daemon`, `#help` **[VERIFY]**
16. Telegram OpenClaw RU **[VERIFY]**
17. Habr / dev.to — поиск `openclaw daemon vps` **[VERIFY]**

**Аналогичные проекты (для сравнения практик):**
18. Claude Code daemon-mode docs (Anthropic) — паттерны daemon для AI-CLI
19. Aider в systemd — gist'ы и blogs
20. Goose by Block — daemon-конфиги, MCP-серверы

---

## 🏁 Итог

После прохождения блока:
- На VPS крутится `openclaw daemon` под systemd user-unit, с `Restart=on-failure`, ограничениями памяти/CPU.
- Gateway доступен **только** на `127.0.0.1` — никакого внешнего сетевого attack-surface.
- `loginctl enable-linger` гарантирует, что демон жив 24/7 независимо от твоих SSH-сессий.
- SSH-туннель в `~/.ssh/config` даёт **тебе одному** доступ к дашборду в одну команду.
- Ребут и logout пережиты — проверено вручную.
- `openclaw doctor` зелёный — можно идти в блок 3 (подключение LLM-провайдеров).

> 🔁 **Финальная просьба** к Дмитрию: перед прогоном на VPS проверь все места **[VERIFY]** против актуальной `docs.openclaw.ai`. Если что-то не сходится — пиши в чат спринта, обновим документ.
