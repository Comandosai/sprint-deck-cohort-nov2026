# Runbook: config-patch

> Hot-reload конфига **без полного рестарта** daemon. Сохраняет активные Telegram-сессии.
> Время: 30 секунд.
> Источник: PRO-02-hidden-features.md (hidden feature #2), блок-02-установка-openclaw.md.

---

## Когда использовать

Если меняешь:
- Текстовые поля (`spending.dailyCapUsd`, `redactPatterns`, `commands.allowlist`).
- MCP-серверы (добавление/удаление).
- Skills entries.
- Channel tokens (Telegram bot token подменился).
- Memory ключи.
- Voice/image модели.

**Когда НЕ использовать (нужен полный restart):**
- Изменил `auth.profiles` (новый провайдер).
- Изменил `tools.profile` (`messaging` → `full`).
- Изменил `sandbox.mode`.
- Изменил `bindings` (где какой агент отвечает).
- Tailscale / network config.

В сомнении — `gateway-restart.md` (полный рестарт безопаснее).

---

## Шаги (30 секунд)

### 1. Включи hot-reload mode (один раз навсегда)

В `config/openclaw.json` уже стоит:
```json
"gateway": { "configReload": "hybrid" }
```

Если не уверен — `cat config/openclaw.json | jq .gateway`.

### 2. Сделай правку локально

Отредактируй `config/openclaw.json`. Например, поменяй `dailyCapUsd: 2 → 5`.

### 3. Зальей на VPS

```bash
# Только конфиг, без всего workspace
rsync -av config/openclaw.json clawd@${VPS_IP}:~/.openclaw/openclaw.json
```

Или через скрипт:
```bash
./scripts/deploy.sh    # он зальёт всё, но это ок
```

### 4. Hot-reload (без рестарта)

```bash
ssh clawd-vps 'openclaw gateway call config.reload'
```

Должно ответить `{"reloaded": true, "sections": [...]}`.

### 5. Верификация

```bash
./scripts/status.sh
```

Daemon должен оставаться `Active`. Активные сессии не прерываются. Smoke-test в Telegram — бот отвечает мгновенно.

---

## Что делать если hot-reload не подхватил изменения

Иногда какая-то секция не реагирует на hybrid reload — нужен полный рестарт:

```bash
ssh clawd-vps 'systemctl --user restart openclaw'
sleep 10
./scripts/status.sh
```

Это не страшно — все Telegram-сессии полупрерывистые (бот при возобновлении просто продолжает).

---

## Edge cases

### Auth/binding не подтягиваются hot-reload

Это known limitation. Решение: после правки `auth` секции — `restart`, не `reload`.

### Telegram token поменялся, polling не подхватил

```bash
ssh clawd-vss 'openclaw channels.telegram.reconnect'
```

Если такой команды нет — `restart`.

### Tailscale / Funnel правки

Эти меняются на уровне OS (`tailscale serve`), а не openclaw. Сам daemon рестартить не нужно.

---

## Откат

```bash
ssh clawd-vps 'cp ~/.openclaw/openclaw.json.backup-* ~/.openclaw/openclaw.json'
ssh clawd-vps 'openclaw gateway call config.reload'
```

`deploy.sh` делает backup автоматически.

---

## Связанные

- `deploy-agent.md` — полный deploy с restart (для крупных изменений).
- `gateway-restart.md` — если что-то всё равно сломалось.
