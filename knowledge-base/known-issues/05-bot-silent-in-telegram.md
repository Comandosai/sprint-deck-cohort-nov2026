# Бот «думает» в Telegram но молчит

> **Симптом**: написал боту «привет», иконка «печатает...» появилась, но **ответа нет**. Через 30 секунд иконка пропадает. Никакой ошибки в Telegram. В SSH `openclaw logs` показывает `fetch-timeout reached`.

---

## 🩺 Диагноз — 4 возможные причины

| # | Причина | Симптом в логах |
|---|---|---|
| 1 | **1008 pairing required** | `gateway closed (1008): pairing required` |
| 2 | **Probe primary падает** | `[fetch-timeout] reached; aborting operation` + provider error |
| 3 | **Sessions_yield застрял** | `[ws] ⇄ res ✓ exec.approval.list` без следующего `model=...` |
| 4 | **Polling vs webhook конфликт** | `409 Conflict: terminated by other getUpdates` |

В **9 случаев из 10** — это №1 (см. `01-1008-pairing-required.md`) или №2 (см. ниже).

## 🩺 Шаги диагностики

⚠️ **СТОП**: не трогай настройки. Сначала собери факты.

```bash
# 1. Что говорит daemon
bash -lc "systemctl --user status openclaw --no-pager | head -10"

# 2. Что в логах за последнюю минуту
bash -lc "openclaw logs --since 1m"

# 3. Какие модели резолвятся
bash -lc "openclaw models status"

# 4. Какие channels активны
bash -lc "openclaw channels list"

# 5. Pairing-state
bash -lc "openclaw devices list"

# 6. doctor
bash -lc "openclaw doctor --deep | tail -30"
```

Покажи выводы AI или консультанту — найдём точку отказа.

## ✅ Фиксы по причинам

### Причина 1: 1008 pairing
→ см. `01-1008-pairing-required.md`. Фикс: переустановка через ручной `openclaw onboard`.

### Причина 2: Probe primary падает (MiniMax)

**Что в логах**:
```
[exec] model=minimax/MiniMax-M2.7 START
[fetch-timeout] reached; aborting operation
[exec] FALLBACK to deepseek/deepseek-v4-flash
[exec] model=deepseek/deepseek-v4-flash ok
```

**Возможные причины**:
- Slug в нижнем регистре → см. `04-slug-case-sensitive.md`
- Битый или просроченный API-ключ → проверь `openclaw auth list`
- Не оплачена подписка MiniMax Coding Plan → platform.minimax.io
- MiniMax API сейчас недоступен → проверь status.minimax.io

**Фикс**:
```bash
# Проверить probe
bash -lc "openclaw models test minimax/MiniMax-M2.7"

# Если ключ — переустановить через onboard или
bash -lc "openclaw auth set minimax --api-key 'sk-...'"
```

### Причина 3: Sessions_yield застрял

**Что в логах**:
```
[ws] ⇄ req exec.approval.list
[ws] ⇄ res ✓ exec.approval.list 313ms
... тишина ...
```

Бот ждёт подтверждения tool call который не приходит. Часто из-за `exec.ask` mode `always`.

**Фикс**:
```bash
# Проверить pending sessions
bash -lc "openclaw sessions"

# Если есть зависшая — отменить
bash -lc "openclaw sessions cancel <session-id>"

# Переключить exec.ask на 'never' для безопасных команд
bash -lc "openclaw config set tools.exec.ask 'never'"
```

### Причина 4: Polling vs webhook

**Что в логах**:
```
[telegram] getUpdates failed: 409 Conflict
```

Это значит **где-то ещё** запущен бот с тем же токеном (другой VPS / dev-машина / webhook включён).

**Фикс**:
```bash
# Удалить webhook (если был)
TG_TOKEN=$(cat ~/.openclaw/secrets/telegram.token)
curl -s "https://api.telegram.org/bot$TG_TOKEN/deleteWebhook"

# Перезапустить daemon
systemctl --user restart openclaw

# Проверить что нигде ещё не запущен
# Если у тебя 2 VPS с одним ботом — останови один
```

## 🛡 Профилактика

- Не запускай два OpenClaw на одном Telegram-токене
- Не включай webhook параллельно с polling
- В Промпте 8 явно: token в файле с `chmod 600` (не в нескольких местах)

## 📚 Связанные

- `01-1008-pairing-required.md` — главная ловушка
- `02-path-non-login-shell.md` — `openclaw: command not found` (тогда тоже бот молчит)
- `04-slug-case-sensitive.md` — fallback на DeepSeek вместо MiniMax
