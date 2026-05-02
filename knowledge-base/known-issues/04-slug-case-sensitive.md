# Slug моделей case-sensitive — `MiniMax` vs `minimax`

> **Симптом**: бот в Telegram отвечает, но в логах модель `deepseek/deepseek-v4-flash` (fallback) вместо `minimax/MiniMax-M2.7` (primary). Probe MiniMax падает молча.

---

## 🩺 Диагноз

OpenClaw сравнивает slug модели **с учётом регистра**:

| Что в конфиге | Результат |
|---|---|
| ✅ `minimax/MiniMax-M2.7` | работает, бот отвечает через MiniMax |
| ❌ `minimax/minimax-m2.7` | provider unknown / probe fails / fallback на DeepSeek |
| ❌ `MINIMAX/minimax-m2.7` | provider unknown |
| ❌ `MiniMax/MiniMax-M2.7` | provider unknown (provider должен быть в нижнем регистре) |

**Правильный формат**: `<provider>/<model-id-as-is-from-provider>`

Provider всегда в нижнем регистре: `minimax`, `deepseek`, `openrouter`, `groq`, `openai`.
Model-id — **как в провайдере**: `MiniMax-M2.7` (с заглавными M).

## ✅ Правильные slug-и для нашего стека

```
minimax/MiniMax-M2.7                    ← primary
deepseek/deepseek-v4-flash              ← fallback (нижний регистр у DeepSeek)
deepseek/deepseek-v4-pro                ← alias premium
deepseek/deepseek-v4-pro:thinking       ← alias think
openrouter/google/gemini-2.5-flash-lite ← heartbeat
openrouter/moonshotai/kimi-k2.6         ← subagents
openrouter/google/gemini-2.5-flash-image ← image primary
openrouter/black-forest-labs/flux-schnell ← image fast
```

## 🔍 Как проверить что у тебя

```bash
# Что в конфиге?
bash -lc "openclaw config get agents.defaults.model.primary"

# Что реально работает?
bash -lc "openclaw models test minimax/MiniMax-M2.7"
bash -lc "openclaw models test minimax/minimax-m2.7"  # должен упасть

# Что в логах после запроса бота?
bash -lc "openclaw logs --since 1m" | grep model=
# Если видишь model=deepseek/... — primary не работает
```

## ✅ Фикс

```bash
# Если slug в нижнем регистре — переустановить:
bash -lc "openclaw config set agents.defaults.model.primary 'minimax/MiniMax-M2.7'"

# Перезапустить daemon чтобы конфиг подхватился
systemctl --user restart openclaw && sleep 5

# Проверить probe
bash -lc "openclaw models test minimax/MiniMax-M2.7"
# Должен ответить ok
```

Если probe упал даже с правильным slug — причина в другом:
- Битый ключ → `openclaw auth list` → проверь что MiniMax есть
- Не оплачена подписка Coding Plan → зайди на platform.minimax.io
- Endpoint сломан → проверь docs.openclaw.ai на актуальный provider URL

## 🐛 Почему случается

Случаи когда slug ломается:
1. **AI лепил конфиг через jq/sed** и сделал toLowerCase() для «безопасности»
2. **Копи-паст из старой документации** — в OpenClaw 2025.x slug были в нижнем регистре
3. **MiniMax переименовал модель** — раньше было `minimax-m2`, стало `MiniMax-M2.7`

## 🛡 Профилактика

В Промпте 0 (meta) v1.5+ явно:
```
КРИТИЧНЫЕ НЮАНСЫ OpenClaw 2026.4.x:
1. SLUG МОДЕЛЕЙ CASE-SENSITIVE
   ✅ minimax/MiniMax-M2.7  (с заглавными M!)
   ❌ minimax/minimax-m2.7  (нижний регистр — модель не найдена)
```

В cheat-sheet onboard (Часть А2 Промпта 6) — пункт 14 с **жирным предупреждением** про заглавные M.

## 📚 Связанные

- `06-runaway-4200-incident.md` — что бывает когда fallback дороже primary
- `07-env-not-in-systemd.md` — env-переменные с ключами не пробрасываются
