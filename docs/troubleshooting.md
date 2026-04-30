# Troubleshooting — топ-10 проблем

> Что делать если что-то пошло не так. Decision tree сверху, детали по каждой проблеме ниже.
> Источник: блок-09-mcp-серверы.md (browser troubleshoot), блок-11-безопасность.md, PRO-04-production-hardening.md, АУДИТ.md.

---

## Decision tree

```
Что-то сломалось?
│
├── Деньги утекают → checklists/emergency-stop.md (СНАЧАЛА)
├── VPS не отвечает → #8 + checklists/disaster-recovery.md
├── Daemon упал, не поднимается → #2 + checklists/gateway-restart.md
├── Бот молчит, daemon живой → #1
├── Browser не работает → #3 (5 причин)
├── Memory не персистит → #6
├── Voice не работает → #7
├── Telegram заблокирован → #9
├── Конфиг сломан → #10
└── Control UI не открывается → #5
```

---

## #1. Бот молчит (daemon живой, но не отвечает)

**Симптомы:**
- `./scripts/status.sh` показывает `Daemon: Active`.
- В Telegram бот не пишет на сообщение в течение 30+ секунд.

**Причины и решения:**

### A. Polling завис
```bash
ssh clawd-vps 'openclaw channels.telegram.status'
```
Если `lastPoll` > 1 мин назад — polling завис. Решение:
```bash
ssh clawd-vps 'openclaw gateway call channels.telegram.reconnect'
```
Если такой команды нет — `gateway-restart.md`.

### B. dmPolicy блокирует
Проверь `openclaw.json`:
```json
"dmPolicy": "allowlist",
"allowFrom": ["${TELEGRAM_USER_ID}"]
```

Если `TELEGRAM_USER_ID` пустой или не твой — бот молча игнорирует. Получи свой ID через `@userinfobot` в Telegram.

### C. Spending cap сработал
```bash
ssh clawd-vps 'openclaw spend --since="today" --json' | jq
```
Если близко к `dailyCapUsd: 2` — поднимешь лимит или дождёшься завтра.

### D. API провайдера лежит
```bash
ssh clawd-vps 'curl -s -o /dev/null -w "%{http_code}" https://api.openrouter.ai/v1/models'
```
Если 5xx — провайдер лежит. `/model premium` переключит на DeepSeek.

---

## #2. Daemon упал

См. **`checklists/gateway-restart.md`** — полный runbook.

Quick:
```bash
ssh clawd-vps 'journalctl --user -u openclaw --since "5 min ago" | tail -50'
ssh clawd-vps 'systemctl --user restart openclaw'
```

Самые частые причины:
- **OOM** (issue #41778) — нужен swap или больший VPS.
- **Config invalid** — JSON синтаксис: `cat openclaw.json | jq`.
- **Port busy** — `lsof -i :18789` → kill.

---

## #3. Browser не работает (5 причин)

**Симптом:** бот говорит «browser tool недоступен» / «не могу открыть страницу» / «browser control timeout».

### 🚨 Быстрая диагностика
```bash
ssh clawd-vps 'openclaw browser doctor --deep'
```

### Причина #3.1 (90% случаев): `tools.profile: "messaging"` ❌

OpenClaw по умолчанию ставит профиль `messaging`, в нём **browser ОТКЛЮЧЁН**.

В `config/openclaw.json` ставь:
```json
"tools": { "profile": "full" }
```
Затем `./scripts/deploy.sh`.

### Причина #3.2: На VPS нет display

Симптом: `cannot open display` / Chrome крашится.

Решение: убедись что в `openclaw.json`:
```json
"browser": {
  "headless": true,
  "args": ["--no-sandbox", "--disable-dev-shm-usage"]
}
```

### Причина #3.3: Snap AppArmor конфликт (Ubuntu)

Симптом: `Failed to start Chrome CDP` / `AppArmor denied`.

Если Chromium ставился через snap (`snap install chromium`) — AppArmor блокирует CDP.

Решение:
```bash
ssh clawd-vps 'sudo snap remove chromium 2>/dev/null'
ssh clawd-vps 'npx playwright install --with-deps chromium'
```
Найди путь:
```bash
ssh clawd-vps 'find ~/.cache/ms-playwright -name chrome -type f'
```
И добавь в `openclaw.json`:
```json
"browser": { "executablePath": "/home/clawd/.cache/ms-playwright/chromium-XXXX/chrome-linux/chrome" }
```

### Причина #3.4: Stale extension relay (legacy < 2026.3.22)

Решение:
```bash
ssh clawd-vps 'openclaw doctor --fix && systemctl --user restart openclaw'
```

### Причина #3.5: Browser control service не запущен

Симптом: `Can't reach the OpenClaw browser control service (timed out after 20000ms)`.

**НЕ retry** — путь в никуда. Решение:
```bash
ssh clawd-vps 'openclaw gateway restart && sleep 5 && openclaw browser doctor --deep'
```

---

## #4. Runaway spending (СРОЧНО)

См. **`checklists/emergency-stop.md`** — полный runbook.

Quick:
```bash
./scripts/emergency-stop.sh
```

Затем:
1. Отзови ключи у провайдеров.
2. Проверь `heartbeat.rateLimit`, `model.fallbacks`, `premiumGuard`.
3. Перезапусти с мониторингом `watch -n 60 ./scripts/status.sh`.

---

## #5. Control UI не открывается

**Симптом:** браузер на `http://localhost:4000` показывает «connection refused».

### A. SSH-туннель не активен
```bash
./scripts/connect.sh    # этот скрипт сам пробрасывает 4000+6333
```
Без него localhost:4000 ничего не значит.

### B. UI отключён в конфиге
Проверь `openclaw.json`:
```json
"ui": {
  "enabled": true,
  "host": "127.0.0.1",
  "port": 4000
}
```

`host: "127.0.0.1"` — НЕ `0.0.0.0`! Иначе UI открыт всему интернету.

### C. Token mismatch
В `openclaw.json` указан `auth.tokenFile`. На VPS должен быть файл `~/.openclaw/secrets/ui.token` с произвольной строкой:
```bash
ssh clawd-vps 'openssl rand -hex 32 > ~/.openclaw/secrets/ui.token && chmod 600 ~/.openclaw/secrets/ui.token'
```

UI запросит этот токен при первом открытии.

### D. mudrii dashboard вместо встроенного UI
Если используешь `mudrii/openclaw-dashboard` — это отдельный сервис на Go. Проверь:
```bash
ssh clawd-vps 'systemctl --user status openclaw-dashboard'
```

---

## #6. Memory не персистит

**Симптом:** бот забывает факты между сессиями.

### A. MEMORY.md не загружается в текущую сессию
- В групповых чатах MEMORY.md **не грузится** — это by design (см. `workspace/AGENTS.md`).
- В sub-agent сессиях — тоже не грузится.
- В main session должно работать. Проверь: `ssh clawd-vps 'cat ~/.openclaw/workspace/MEMORY.md | head -20'`.

### B. Vector memory (Qdrant) не запущен
```bash
ssh clawd-vps 'docker ps | grep qdrant'
```
Если контейнера нет:
```bash
ssh clawd-vps 'cd ~/.openclaw && docker compose -f docker-compose.qdrant.yml up -d'
```

### C. Mem0 npm-пакет не установлен
```bash
ssh clawd-vps 'npm list -g | grep mem0'
```
Должен быть `@mem0/openclaw-mem0@1.0.10` или новее.

### D. Daily logs пишутся в /tmp, не в memory/
Проверь `openclaw.json`:
```json
"memory": {
  "dailyLogs": {
    "enabled": true,
    "path": "memory/{YYYY-MM-DD}.md"
  }
}
```

Путь относительно workspace (`~/.openclaw/workspace/memory/`).

---

## #7. Voice не работает

**Симптом:** бот не отвечает голосом / не транскрибирует входящие голосовые.

### A. GROQ_API_KEY пустой (Whisper не работает)
В `.env`:
```
GROQ_API_KEY=gsk_...
```
Получи на console.groq.com. Бесплатно 30k минут/мес.

### B. OPENAI_API_KEY пустой (TTS не работает)
TTS — это OpenAI `tts-1`. Без ключа бот ответит текстом.

### C. `transcribeVoiceMessages: false`
Проверь `openclaw.json` → `channels.telegram.accounts.main.transcribeVoiceMessages: true`.

### D. Аудио длиннее 5 минут
`audioMaxDurationSec: 300` — больше 5 минут отбрасывается. Увеличь если нужно.

### E. ffmpeg не установлен
Whisper требует ffmpeg для конвертации. Поставь:
```bash
ssh clawd-vps 'sudo apt install -y ffmpeg'
```

---

## #8. VPS не отвечает совсем

**Симптом:** `ssh clawd-vps` зависает, `ping <VPS_IP>` без ответа.

### A. Проверка у провайдера
- Зайди в личный кабинет Hetzner / Beget / DO.
- Посмотри статус сервера. Ребут через панель если завис.

### B. Если сервер работает, но SSH не идёт
- Возможно `fail2ban` забанил твой IP (3 неудачные попытки). Подожди 10 минут или зайди через консоль провайдера и сними бан: `sudo fail2ban-client unban <твой_IP>`.
- Проверь не сменился ли IP у твоего интернета.

### C. Если сервер дохлый совсем
→ **`checklists/disaster-recovery.md`** — восстановление за 30 минут.

---

## #9. Telegram заблокирован

**Симптом:** бот не получает сообщения, `lastPoll` старше часа.

### A. Российский RKN
В РФ Telegram периодически блокируют. На VPS вне РФ (Hetzner DE/FI/US, Beget с НЕ-российскими IP) — должно работать.

Если VPS в РФ:
- Поставь WireGuard / V2Ray на VPS до европейского узла.
- Или хостинг в EU.

### B. Bot token revoked
Проверь:
```bash
ssh clawd-vps 'curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"'
```
Если 401 — токен отозван. Получи новый у `@BotFather`.

### C. Webhook конфликт
Если кто-то выставил webhook на бота — polling не работает. Сбрось:
```bash
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteWebhook"
```

---

## #10. Конфиг сломан

**Симптом:** daemon при рестарте падает с `Invalid config` / `JSON parse error`.

### Локально
```bash
python3 -c "import json; json.load(open('config/openclaw.json'))"
```
Покажет точную строку с ошибкой.

### На VPS
```bash
ssh clawd-vps 'cat ~/.openclaw/openclaw.json | jq'
```
`jq` покажет ошибку. Или `python3 -m json.tool`.

### Откат
```bash
ssh clawd-vps 'ls -la ~/.openclaw/openclaw.json.backup-*'
ssh clawd-vps 'cp ~/.openclaw/openclaw.json.backup-<latest> ~/.openclaw/openclaw.json'
ssh clawd-vps 'systemctl --user restart openclaw'
```

`deploy.sh` делает backup перед каждым деплоем.

---

## Как сообщить о проблеме

Если ничего не помогает:
1. Собери диагностику:
   ```bash
   ssh clawd-vps 'journalctl --user -u openclaw --since "1 day ago" --no-pager' > incident.log
   ssh clawd-vps 'openclaw doctor --deep --json' > doctor.json
   cat config/openclaw.json | jq 'del(.auth)' > config-redacted.json    # без секретов
   ```
2. Открой issue на github.com/openclaw/openclaw с этими файлами.
3. Или напиши в Discord OpenClaw / в наш чат.

**НЕ публикуй `~/.openclaw/secrets/`, `.env`, `auth` секцию из openclaw.json — там токены.**
