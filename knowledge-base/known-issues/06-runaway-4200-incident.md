# Runaway-инцидент — $4200 за 63 часа

> **Симптом**: внезапный счёт от OpenRouter / OpenAI на сотни/тысячи долларов за короткий период. Daemon что-то «думает» в логах, токены кончаются.

---

## 🩺 Реальный кейс из community

Пользователь OpenClaw настроил каскад моделей **неправильно**:
- **Primary**: `minimax/MiniMax-M2.7` ($10/мес фикс. подписка)
- **Fallback**: `anthropic/claude-sonnet-4.6` (~$3 / 1M токенов)

Что произошло:
1. MiniMax вернул `429 rate limit` (или `5xx`)
2. OpenClaw переключился на fallback Sonnet
3. Sonnet ответил, но **через 5 минут** MiniMax всё ещё возвращал ошибку
4. Каждый последующий запрос (включая heartbeat каждые 60 сек) — через Sonnet
5. **63 часа в loop'е** → **$4 200 счёт**

Пользователь не заметил потому что:
- Watchdog не был настроен
- Spending limit на OpenRouter не был выставлен
- Heartbeat без rate-limit жрал по запросу каждые 60 сек

## 🎯 Корневая причина

**Fallback дороже primary**. Когда primary упал — fallback срабатывает на 100% запросов. Если fallback **дороже** — это runaway-сценарий.

## ✅ Правило: fallback ВСЕГДА дешевле primary

| Модель | Уровень | Стоимость | Роль |
|---|---|---|---|
| MiniMax M2.7 | Primary | $10/мес фикс | основной диалог |
| **DeepSeek V4-Flash** | **Fallback** | **~$0.01/1M токенов** | страховка |
| Gemini Flash-Lite | Heartbeat | ~$0.10/мес всего | фоновый |
| Kimi K2.6 | Subagents | ~$1.50/мес | параллельные задачи |
| DeepSeek V4-Pro | Premium (по `/premium`) | по запросу | глубокое мышление |

**Никогда** не ставь Sonnet, GPT-4, Opus в fallback на дешёвый primary.

## 🛡 4 уровня защиты от runaway

### Уровень 1: правильный каскад (см. выше)
Fallback ВСЕГДА дешевле primary.

### Уровень 2: Spending Limit на провайдерах

**OpenRouter** (главный риск — много моделей через один ключ):
- openrouter.ai → Settings → **Spending Limit** → $30/мес
- Это hard cap — после $30 любой запрос упадёт с `403 spending limit reached`

**OpenAI**:
- platform.openai.com → Billing → Usage limits → $10/мес

**Anthropic**:
- console.anthropic.com → Usage → Spend Cap → $20/мес

### Уровень 3: Watchdog cron на VPS

Скрипт `~/.openclaw/scripts/watchdog.sh` запускается каждые 30 минут. Если расход за последний час > $3:
- Остановить daemon (`systemctl --user stop openclaw`)
- Послать alert в Telegram
- Залогировать инцидент

См. Промпт 8 в `workshop-1/01-prompts.md` — готовый шаблон watchdog.

### Уровень 4: Heartbeat rate-limit

В OpenClaw 2026.4.x heartbeat по умолчанию каждые 60 сек. На дешёвой модели (Gemini Flash-Lite) это безопасно. Но если по какой-то причине heartbeat пошёл через дорогую — это $$$.

В конфиге:
```json
"agents": {
  "defaults": {
    "heartbeat": {
      "model": "openrouter/google/gemini-2.5-flash-lite",
      "every": "60m",          ← 60 минут (НЕ 60 секунд!)
      "lightContext": true,    ← минимальный prompt
      "isolatedSession": true  ← НЕ продолжать диалог
    }
  }
}
```

## 🚨 Если runaway уже идёт

**Срочные действия** (в порядке приоритета):

```bash
# 1. Остановить daemon на VPS (не разбирайся, просто стоп)
ssh clawd@VPS 'systemctl --user stop openclaw'

# 2. Проверить расход
bash -lc "openclaw spend --since 24h"

# 3. Заблокировать ключи провайдеров (через их веб-интерфейс)
# - openrouter.ai → Keys → Revoke
# - platform.openai.com → API keys → Revoke
# - и т.д.

# 4. Найти кто кушал
bash -lc "openclaw logs --since 24h" | grep model= | sort | uniq -c | sort -rn

# 5. Подать диспут провайдеру если действительно был баг
```

## 🛡 Профилактика на старте

В Промпте 7 (alias) и Промпте 8 (watchdog) v1.5+ явно прописано:
- Fallback **только дешевле primary**
- Watchdog **обязателен** до того как пользоваться ботом активно
- Spending Limit на OpenRouter **обязателен**

В Промпте 0 (meta):
```
4. НИКОГДА не ставь модели дороже primary в fallback.
   Реальный кейс: $4200 за 63 часа из-за loop fallback.
   Только дешевле primary.
```

## 📚 Связанные

- `04-slug-case-sensitive.md` — почему primary может «упасть» (battle slug)
- `07-env-not-in-systemd.md` — почему ключи не резолвятся (тогда fallback не сработает вообще)
