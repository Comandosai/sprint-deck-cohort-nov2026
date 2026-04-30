# Runbook: gateway-restart

> Gateway завис, daemon упал, бот не отвечает в Telegram.
> Время: 1-3 минуты.
> Источник: блок-02-установка-openclaw.md, PRO-04-production-hardening.md.

---

## Симптомы

- Бот молчит в Telegram > 1 минуты на простой вопрос.
- `./scripts/status.sh` показывает `Daemon: Down` или `Gateway: Not listening`.
- Telegram говорит «бот не отвечает» (стандартное сообщение).
- В дашборде на `localhost:4000` — connection refused.

Если деньги утекают — сначала `emergency-stop.md`, потом сюда.

---

## Шаги

### 1. Подключись к VPS

```bash
./scripts/connect.sh
```

### 2. Проверь статус

```bash
systemctl --user status openclaw
```

Возможные сценарии:

#### A. `inactive (dead)` — daemon просто упал

```bash
systemctl --user start openclaw
sleep 5
systemctl --user is-active openclaw
```

Если `active` — готово, проверяй в Telegram. Если опять упал — см. секцию «Анализ логов».

#### B. `failed` — упал с ошибкой

```bash
systemctl --user reset-failed openclaw
journalctl --user -u openclaw --since "5 min ago" | tail -50
systemctl --user start openclaw
```

#### C. `active (running)` — но бот всё равно молчит

Daemon живой, но gateway завис. Полный рестарт:

```bash
systemctl --user restart openclaw
sleep 10
openclaw gateway status      # должен ответить healthy
```

### 3. Анализ логов (если daemon не поднимается)

```bash
journalctl --user -u openclaw --since "10 min ago" --no-pager | tail -100
```

Типовые причины:
- **OOM kill** (issue #41778) — daemon вышел за `MemoryMax=2G`. Решение: добавь swap или повысь VPS RAM.
- **Port already in use** — `lsof -i :18789` → kill процесс.
- **Config invalid** — JSON синтаксис сломан: `cat ~/.openclaw/openclaw.json | jq` → найди ошибку.
- **Missing API key** — в `.env` пустые поля. На VPS лежат в `~/.openclaw/secrets/`. Проверь через `ls -la ~/.openclaw/secrets/`.

### 4. Если ничего не помогает — полный reload

```bash
systemctl --user daemon-reload
systemctl --user restart openclaw
sleep 10
openclaw doctor --deep
```

### 5. Финальная проверка

```bash
exit                          # выйди из SSH
./scripts/status.sh            # с локальной машины
```

Telegram smoke-test: «Привет?» → ответ в течение 5 секунд.

---

## Если по-прежнему лежит

- Проверь VPS живой: `ping <VPS_IP>`. Если нет — `disaster-recovery.md`.
- Проверь баланс провайдеров (MiniMax, DeepSeek, OpenRouter) — если кончились деньги, daemon работает но запросы 402.
- Проверь интернет на VPS: `ssh clawd-vps 'curl -s https://api.openrouter.ai/v1/models | head'`.

Если совсем жопа — `disaster-recovery.md`.

---

## Превенция

- Включён `Restart=on-failure` в systemd unit — daemon сам поднимется после crash.
- `MemoryMax=2G` + swap файл 2G — OOM не должен ронять daemon.
- Watchdog cron каждые 30 мин (см. блок-12) — отдельный процесс проверяет daemon.

Если рестарт повторяется > 5 раз за 5 минут — `StartLimitBurst=5` остановит зацикливание. Ручной reset: `systemctl --user reset-failed openclaw`.

---

## Связанные

- `emergency-stop.md` — если деньги утекают.
- `disaster-recovery.md` — если VPS не отвечает совсем.
- `docs/troubleshooting.md` — топ-10 проблем (включая «Бот молчит»).
