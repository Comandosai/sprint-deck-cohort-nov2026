# Runbook: emergency-stop

> 🚨 **Деньги утекают. Бот на петле. Нужно ОСТАНОВИТЬ за 10 секунд.**
> Источник: блок-11-безопасность.md, PRO-04-production-hardening.md.

---

## Шаг 1 — ОСТАНОВИ DAEMON (5 секунд)

С локальной машины:

```bash
./scripts/emergency-stop.sh
```

Или если скрипт недоступен:

```bash
ssh clawd-vps 'systemctl --user stop openclaw'
```

Или через AI-плагин в Antigravity:
> Останови OpenClaw немедленно: `ssh clawd-vps 'systemctl --user stop openclaw'`

**Daemon остановлен — больше никаких LLM-запросов.**

---

## Шаг 2 — Отзови API-ключи (60 секунд)

Если уверен что что-то всерьёз пошло не так — отзови ключи у провайдеров. Это **гарантия** что даже если daemon включится — все запросы упадут с 401.

| Провайдер | Где |
|---|---|
| MiniMax | platform.minimax.io → API Keys → Revoke |
| DeepSeek | api-docs.deepseek.com → Keys → Delete |
| OpenRouter | openrouter.ai → Settings → Keys → Revoke |
| Groq | console.groq.com → Keys → Delete |
| OpenAI (если используешь TTS) | platform.openai.com → API keys → Revoke |

После отзыва — выпишешь новые потом, когда исправишь причину.

---

## Шаг 3 — Посчитай ущерб (30 секунд)

```bash
ssh clawd-vps 'openclaw spend --since="-24h" --json' | jq
```

Или в личных кабинетах провайдеров (Usage / Billing / Activity).

Запиши цифру. Понадобится при общении с поддержкой провайдера, если потери серьёзные.

---

## Шаг 4 — Найди причину

### Cause A: Heartbeat в loop без rate limit (90% случаев)

**Симптом:** в логах heartbeat запускается каждые 30 секунд вместо 60 минут.

**Проверка:**
```bash
ssh clawd-vps 'cat ~/.openclaw/openclaw.json | jq .agents.defaults.heartbeat'
```

Должно быть:
```json
{
  "every": "60m",
  "rateLimit": {"perMinute": 1, "perHour": 5, "perDay": 50}
}
```

Если `rateLimit` нет или `every: "1m"` — это твоя причина.

### Cause B: Fallback на дорогую модель

**Симптом:** primary упал, daemon фолбэкнулся на Sonnet/Opus = в 100x дороже.

**Проверка:**
```bash
ssh clawd-vps 'cat ~/.openclaw/openclaw.json | jq .agents.defaults.model.fallbacks'
```

Должно быть `["deepseek/deepseek-v4-flash"]` — **дешевле primary!**

Если в fallback вписан Sonnet/Opus — это твоя причина.

### Cause C: Premium забыли выключить

**Симптом:** `/model premium` активирован, забыл выключить, 100 сообщений в премиум-режиме.

**Проверка:**
```bash
ssh clawd-vps 'cat ~/.openclaw/openclaw.json | jq .premiumGuard'
```

Должно быть `{"expireAfterMessages": 5}`.

### Cause D: Subagents без spending cap

**Симптом:** какой-то skill вызвал `sessions_spawn` в loop, плодит sub-agents.

**Проверка логов:**
```bash
ssh clawd-vps 'journalctl --user -u openclaw --since "1 hour ago" -g sessions_spawn | wc -l'
```

> 100 за час — это **точно loop**.

### Cause E: Browser tool на бесконечном scroll

**Симптом:** browser открыл страницу с infinite scroll, читает 1000 страниц.

**Проверка:**
```bash
ssh clawd-vps 'journalctl --user -u openclaw --since "1 hour ago" -g browser | tail -50'
```

---

## Шаг 5 — Исправь конфиг

```bash
# На VPS — backup сломанного для разбора потом
ssh clawd-vps 'cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.broken-$(date +%s)'
```

Локально исправь `config/openclaw.json` — убери проблемную часть (см. Cause A-E выше).

После проверь, что в нём всё на месте:
- `spending.dailyCapUsd: 2`
- `spending.killSwitchAt: 5`
- `agents.defaults.heartbeat.rateLimit` есть
- `agents.defaults.model.fallbacks` только дешёвые
- `premiumGuard.expireAfterMessages: 5`

```bash
./scripts/deploy.sh    # перельёт конфиг
```

---

## Шаг 6 — Перезапусти осторожно

Daemon ещё остановлен. Запусти **с мониторингом**:

```bash
ssh clawd-vps 'systemctl --user start openclaw'
sleep 5
./scripts/status.sh
```

**Мониторь spend в реальном времени 10 минут:**

```bash
watch -n 60 './scripts/status.sh'
```

Если spend начал расти быстро снова — `Ctrl+C` → `emergency-stop.sh` → пиши в чат.

---

## Шаг 7 — Что с деньгами?

### MiniMax
Подписка $10/мес фиксированная — **переплата невозможна**. Это её главное преимущество.

### DeepSeek
Списания в реальном времени с баланса. Если баланс кончился — провайдер сам стопит запросы (это в нашу пользу).

### OpenRouter
**Spending Limit $30/мес** должен был сработать. Если сработал — ключ залочен. Если нет — у тебя не настроен лимит в Settings (поставь сейчас).

### OpenAI / Anthropic
Списание с карты в реальном времени. Если хард-лимит установлен в личном кабинете — он защитит.

### Если ущерб > $50

1. Свяжись с поддержкой провайдера. **Они иногда возвращают** деньги при инциденте, особенно OpenRouter и Anthropic.
2. Сохрани логи:
   ```bash
   ssh clawd-vps 'journalctl --user -u openclaw --since "1 day ago" --no-pager' > incident-logs.txt
   ```
3. Это поможет провайдеру оценить «known bug or user error».

---

## Превенция (4 уровня защиты — все уже в config/openclaw.json)

1. **Config cap** — `spending.dailyCapUsd: 2`, `monthlyCapUsd: 30`, `killSwitchAt: 5`.
2. **Provider hard limit** — OpenRouter $30/мес (включи в Settings провайдера!).
3. **Watchdog kill-switch** — cron каждые 30 мин: `if openclaw spend > $5/час: stop daemon`.
4. **Heartbeat rate limit** — `1/мин, 5/час, 50/день`.

Если хоть один из 4 не настроен — настрой **сейчас**, не жди инцидента №2.

---

**Спокойствие. Цель — не сжечь больше денег и понять причину. Daemon остановлен, риска нет. Дальше уже спокойно разбираемся.**
