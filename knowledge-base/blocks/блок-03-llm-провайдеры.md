# Блок 3: LLM-провайдеры и модели

> **Что:** настройка каскада LLM через OpenRouter — Kimi K2.5/K2.6 как основная рабочая лошадка, Gemini 2.5 Flash-Lite на heartbeat, DeepSeek V4 Flash на subagents, Claude Sonnet 4.6 на премиум-задачи.
> **Зачем:** получить «достаточно умного» агента за разумные деньги — реальная экономия 60–85% против «всё на Claude Opus», без потери качества на критичных задачах.
> **Время:** 35–50 минут (а не 30 — БСОД с onboarding wizard стоит закладывать).

---

## ⚠️ Корректировки к исходному заданию

1. **Kimi K2.5 — реальная модель, существует на OpenRouter** (model ID `moonshotai/kimi-k2.5`, релиз 27 января 2026). Цена: **$0.44/Mt input, $2.00/Mt output**, контекст 262 144 токенов. Однако по состоянию на апрель 2026 уже доступна более свежая **Kimi K2.6** ($0.7448/Mt in, $4.655/Mt out) с интеллектом 54 на Artificial Analysis Index — выше, чем K2.5, и значительно дешевле Claude/GPT-5. **Рекомендация: использовать K2.6 как primary, а K2.5 — как первый fallback** (он дешевле в 1.7×, и при перегрузках K2.6 переключение почти бесшовно).
2. **DeepSeek V3 устарел.** 24 апреля 2026 Moonshot/DeepSeek выпустили **DeepSeek V4 Pro** (1.6T MoE, 49B активных, 1M контекст, **$0.435/$0.87** за Mt) и **DeepSeek V4 Flash** (284B MoE, 13B активных, **$0.14/$0.28** — это эталон цена/качество для subagents). Для subagents бери **V4 Flash**, не V3.
3. **«Spending caps $2/день» в OpenRouter** — настраиваются на уровне API-ключа (daily/weekly/monthly credit limit), это подтверждено в `/docs/api/reference/limits` и Guardrails. Точных сценариев в документации немного — раздел про настройку даю с пометкой [VERIFY UI].
4. **Heartbeat / subagent / премиум** — это реальные конфиг-поля OpenClaw: `agents.defaults.heartbeat.model`, `agents.defaults.subagents.model`. Подтверждены в docs.openclaw.ai и в issues GitHub.

---

## 🎯 Цель блока

Получить рабочую конфигурацию OpenClaw, в которой:
- 80% запросов уходит на **дешёвую быструю модель** (Kimi K2.6/K2.5) — основные диалоги, code edits, reasoning среднего уровня;
- фоновые heartbeat-проверки (раз в 30 мин) идут на **самую дешёвую** Gemini 2.5 Flash-Lite — там просто не нужен интеллект;
- параллельные subagent-задачи (поиск, парсинг, мелкие правки) уходят на **DeepSeek V4 Flash** — он быстрый и копеечный;
- по команде `/model premium` (или вручную в config) включается **Claude Sonnet 4.6** — для архитектурных решений, крупных рефакторингов, всего, где цена ошибки выше цены токена;
- настроен **fallback-chain** на случай rate-limits / падений провайдера;
- **prompt caching** включён там, где это поддерживается (Anthropic, DeepSeek, Gemini, Moonshot) — −90% на повторяющихся системных промптах;
- настроен **daily spending cap** $2 — чтобы петля subagent'ов не съела депозит за ночь.

---

## ⚡ Что нового в апреле 2026

| Событие | Дата | Влияние на блок |
|---|---|---|
| **DeepSeek V4 Pro / V4 Flash** релиз (MIT licence, 1M контекст) | 24 апр 2026 | V4 Flash — лучший вариант для subagents, $0.14/$0.28 за Mt |
| **Kimi K2.6** на OpenRouter | апрель 2026 | Интеллект 54 (между Claude Sonnet 4.6 и GPT-5.4), цена $1.7 effective |
| **Claude Sonnet 4.7** (Opus 4.7 уже на Artificial Analysis с интеллектом 57) | весна 2026 | для премиум-роли можно брать 4.6 (стабильно) или 4.7 (флагман) |
| **OpenRouter: 1M бесплатных BYOK-запросов в месяц** | с 1 окт 2025 | Если вы уже платите Anthropic/OpenAI напрямую — BYOK = роутинг бесплатно до 1M req/мес |
| **Gemini 3.1 Pro Preview** | начало 2026 | интеллект 57, скорость 122 t/s — конкурент Sonnet, но в этом каскаде не нужен |
| **GPT-5.5 (xhigh)** | 2026 | топ-1 интеллект 60, $11.3/Mt — слишком дорого для primary, оставьте как fallback премиума |
| **Implicit prompt caching** на DeepSeek/Gemini 2.5/Groq/Moonshot | 2026 | Кэширование «бесплатно из коробки», без cache_control breakpoints |

---

## 🛠️ Конкретные инструменты и версии

### Каскад моделей (рекомендация апреля 2026)

| Модель | Model ID на OpenRouter | $/Mt input | $/Mt output | Контекст | Применение | Источник |
|---|---|---|---|---|---|---|
| **Kimi K2.6** | `moonshotai/kimi-k2.6` | $0.7448 | $4.655 | ~256k [VERIFY] | Primary (основные диалоги, код, reasoning) | openrouter.ai/moonshotai/kimi-k2.6 |
| **Kimi K2.5** | `moonshotai/kimi-k2.5` | $0.44 | $2.00 | 262 144 | Primary fallback / альтернатива К2.6 | openrouter.ai/moonshotai/kimi-k2.5 |
| **Gemini 2.5 Flash-Lite** | `google/gemini-2.5-flash-lite` | $0.10 | $0.40 | 1 048 576 | Heartbeat (фоновые «ты жив?» проверки) | openrouter.ai/google/gemini-2.5-flash-lite |
| **DeepSeek V4 Flash** | `deepseek/deepseek-v4-flash` [VERIFY exact slug] | $0.14 | $0.28 | 1 000 000 | Subagents (parallel-задачи) | openrouter.ai/deepseek/... (объявлен 24 апр 2026) |
| **DeepSeek V3.2** | `deepseek/deepseek-v3.2` | $0.252 | $0.378 | ~128k [VERIFY] | Резервный subagent-fallback | openrouter.ai/deepseek/deepseek-v3.2 |
| **Claude Sonnet 4.6** | `anthropic/claude-sonnet-4.6` | $3.00 | $15.00 | 1 000 000 | Premium (архитектура, важное) | openrouter.ai/anthropic/claude-sonnet-4.6 |
| **Claude Sonnet 4.5** | `anthropic/claude-sonnet-4.5` | $3.00 | $15.00 | 1 000 000 | Premium fallback | openrouter.ai/anthropic/claude-sonnet-4.5 |
| **Claude Haiku 4.5** | `anthropic/claude-haiku-4.5` | [VERIFY] | [VERIFY] | ~200k [VERIFY] | Cheap-Anthropic fallback (для prompt cache) | openrouter.ai/anthropic |
| **GPT-5.4 (xhigh)** | `openai/gpt-5.4` [VERIFY slug] | $5.6 effective | [VERIFY] | [VERIFY] | Premium-fallback альтернатива | artificialanalysis.ai |

### Через OpenRouter ID-формат для OpenClaw

В OpenClaw модели через OpenRouter указываются как **`openrouter/<author>/<slug>`** — не просто `<author>/<slug>`. Пример: `openrouter/moonshotai/kimi-k2.6`. Это критично — без `openrouter/` префикса OpenClaw попытается найти прямого провайдера.

### Альтернативы OpenRouter (если нужна максимальная скорость)

| Провайдер | Сильная сторона | Когда брать |
|---|---|---|
| **Groq** (LPU) | 0.6–0.9с TTFT, ~500 t/s на 70B | Если нужны мгновенные ответы пользователю в Telegram |
| **Cerebras** (WSE) | ~3000 t/s на gpt-oss-120B | Экстремальная скорость, но узкий каталог |
| **Fireworks AI** | Production reliability, structured outputs | Если упирается в structured output / function calling |
| **Together AI** | Широкий каталог open-source + fine-tuning | Кастомные модели |
| **DeepInfra** | Часто дешевле OpenRouter на open-weights | Долгосрочно, для high-volume |

Для блок-3 **остаёмся на OpenRouter** — он покрывает 60+ провайдеров одним ключом, поддерживает BYOK и фолбэки из коробки.

### Логирование (опционально, в блок-3 не критично)

- **Langfuse** (open-source, self-hosted) — лучший выбор для debugging promp+ caching hit rate.
- **Helicone** — proxy-based, проще подключить, отдельный layer на OpenRouter.
- **LiteLLM proxy** — нужен только если хочешь усреднить 5+ провайдеров за единым OpenAI-совместимым API. Для OpenClaw + OpenRouter **не нужен** (OpenRouter сам этим занимается).

---

## 💡 Лайфхаки и про-приёмы

### 1. Включи implicit prompt caching на DeepSeek/Gemini/Moonshot — это бесплатно
DeepSeek V4, Gemini 2.5 Flash-Lite, Kimi K2.x, Groq и OpenAI поддерживают **implicit caching** — без `cache_control`-блоков, OpenRouter сам видит совпадающие префиксы и берёт reduced rate. Cache read у DeepSeek = ~10% от input price. На системном промпте OpenClaw (≈3–8к токенов) это **−70–90% стоимости** входа на каждом сообщении после первого. Ничего настраивать не надо — просто работает.

### 2. На Anthropic ставь explicit `cache_control` через `cacheRetention` в OpenClaw config
Anthropic единственный среди топов требует **explicit caching**. В OpenClaw есть параметр `cacheRetention: "long"` (1 hour TTL = 2× input на запись, 0.10× на чтение). Поставь `long` для системного промпта SOUL.md/IDENTITY.md — за 50 запросов он отбивается.

### 3. Используй `openrouter/openrouter/auto` как умный роутер
Это не модель, а meta-роутер OpenRouter — он сам выбирает дешёвую модель для простых запросов и капабельную для сложных. Хороший вариант для **heartbeat-fallback**, если не хочешь жёстко прибивать к Gemini Flash-Lite.

### 4. Fallback-chain в OpenClaw — это `agents.defaults.model.fallbacks`, массив
OpenClaw сам управляет фолбэками поверх OpenRouter. Если первая модель вернула ошибку (rate limit, downtime, context overflow) — берётся следующая. Лайфхак: **первый fallback ставь на ту же провайдерскую семью** (K2.6 → K2.5), чтобы поведение не «прыгало» по тону. Второй fallback — другой провайдер (DeepSeek), третий — Claude Haiku как «выживет всегда».

### 5. Subagents всегда на копеечной модели
Subagent — это параллельная задача (поиск файла, grep по 100 файлам, коротенький рефакторинг). Туда **категорически не надо** Claude Sonnet — DeepSeek V4 Flash справляется за $0.14/$0.28, экономия 20–50× за один спан subagent'ов. Подтверждено в документации OpenClaw `/tools/subagents`: поле `agents.defaults.subagents.model`.

### 6. Heartbeat — это «ты жив?» каждые 30 минут, ставь самую дешёвую
Gemini 2.5 Flash-Lite ($0.10/$0.40) — лучший выбор. На 48 heartbeats в день это <$0.01. Кстати, **известный баг #19445** в OpenClaw: при `agents.defaults.heartbeat.isolatedSession: true` модель heartbeat'а иногда сбрасывается на primary. Решение — ставь `isolatedSession: false` явно (или совсем не трогай поле, default false).

### 7. Daily cap $2 — настрой на уровне API-ключа OpenRouter, не в OpenClaw
В OpenRouter dashboard → API Keys → Edit → **Credit Limit + Reset Schedule (daily/weekly/monthly)**. Запросы свыше лимита возвращают 402 — fallback в OpenClaw не сработает (это не rate-limit, а exhausted credit). **Лайфхак:** заведи **два ключа** — основной с cap $2/день, аварийный с cap $5 без daily reset. В OpenClaw поставь оба через `auth.profiles` — первый primary, второй fallback. Если основной упрётся в cap, OpenClaw перейдёт на запасной. [VERIFY: проверить, что OpenClaw действительно умеет переключать API-ключи через профили — поле `auth.profiles` подтверждено в docs, но автоматическое переключение между профилями нужно тестировать]

### 8. BYOK = бесплатный роутинг до 1M req/мес
Если у тебя уже есть Anthropic/OpenAI/Gemini API-ключ с лимитом — добавь его в OpenRouter dashboard → Settings → Integrations → BYOK. OpenRouter будет ходить **твоим** ключом, **бесплатно до 1М запросов в месяц**, после — 5% наценка. Идеально, если уже куплено $50 Anthropic-кредитов: получаешь fallback'и через OpenRouter, но платишь напрямую Anthropic по их ценам.

### 9. Premium-канал через `/model` — реализуется в OpenClaw через model alias
В config-объекте `agents.defaults.models` можно дать алиасы: `"anthropic/claude-sonnet-4.6": { "alias": "premium" }`. Тогда команда `/model premium` в чате переключит сессию на Sonnet. Рекомендую алиасы: `primary` (Kimi), `cheap` (Flash-Lite), `parallel` (DeepSeek Flash), `premium` (Sonnet 4.6), `boss` (Sonnet 4.6 + extended thinking).

### 10. Reasoning-модели включай вручную, не как primary
Claude extended thinking, DeepSeek-Reasoner, OpenAI o3 — стоят дорого (output ×3–10) и медленные. **Никогда** не ставь reasoning-модель как primary в общий чат. Используй только для отдельной команды типа `/think` или для конкретных subagent-ролей (security-review, architecture-decision). На обычные диалоги reasoning не оправдан.

### 11. Бенчмарь под себя, не доверяй усреднённым leaderboard'ам
Artificial Analysis Index хорош как ориентир, но твой кейс (русский язык + tool-calling + длинные системные промпты) уникален. Запусти `openclaw models test` (или эквивалент — см. чек-лист) с 10 типичными твоими запросами на 3–4 моделях и сравни **по факту**. У меня (по разным репортам) Kimi K2.6 на русском заметно лучше, чем DeepSeek V3.2.

### 12. Vision + длинный контекст — не по умолчанию, отдельные слоты
Если нужен анализ скриншота — конфигурируй `agents.defaults.imageModel.primary` отдельно (Kimi K2.5/K2.6 нативно мультимодальны и стоят как обычный текст — это хорошо). Для 1М контекста (анализ всего репо) переключайся вручную на DeepSeek V4 Pro или Gemini 2.5 Flash-Lite (тот тоже 1M).

---

## 📋 Готовые команды и конфиги

### Шаг 1. Регистрация и пополнение OpenRouter

```bash
# 1. Перейти https://openrouter.ai → Sign in (Google/GitHub OAuth)
# 2. Settings → Credits → Add Credits → $10 (минимум)
# 3. API Keys → Create Key
#    Имя: openclaw-primary
#    Credit Limit: 2.00 USD
#    Reset Schedule: Daily   <-- это и есть spending cap $2/день
# 4. Скопировать ключ (начинается с sk-or-...) — он показывается ОДИН РАЗ
```

[VERIFY UI]: точные названия полей в OpenRouter dashboard могут немного отличаться. Главное — найти "Credit Limit" + "Reset Schedule". Это документировано в openrouter.ai/docs/api/reference/limits и /docs/guides/features/guardrails.

### Шаг 2. Установка API-ключа в OpenClaw

```bash
# Вариант A — через wizard (проще)
openclaw onboard --auth-choice openrouter-api-key
# → введёшь ключ интерактивно, он сохранится в keychain

# Вариант B — env-переменная (для CI/headless)
export OPENROUTER_API_KEY="sk-or-..."
echo 'export OPENROUTER_API_KEY="sk-or-..."' >> ~/.zshrc
```

### Шаг 3. openclaw.json фрагмент с каскадом

Файл: `~/.openclaw/openclaw.json` (создаётся onboard'ом, дополняй вручную или через `openclaw config set`):

```json5
{
  "env": {
    "OPENROUTER_API_KEY": "sk-or-..."
  },
  "auth": {
    "profiles": {
      "openrouter:default": {
        "provider": "openrouter",
        "mode": "api_key"
      }
    }
  },
  "agents": {
    "defaults": {
      // === PRIMARY: основная рабочая лошадка ===
      "model": {
        "primary": "openrouter/moonshotai/kimi-k2.6",
        "fallbacks": [
          "openrouter/moonshotai/kimi-k2.5",
          "openrouter/deepseek/deepseek-v4-flash",  // [VERIFY exact slug]
          "openrouter/anthropic/claude-haiku-4.5"
        ]
      },

      // === Каталог моделей с алиасами для команды /model ===
      "models": {
        "openrouter/moonshotai/kimi-k2.6":         { "alias": "primary" },
        "openrouter/moonshotai/kimi-k2.5":         { "alias": "k2" },
        "openrouter/google/gemini-2.5-flash-lite": { "alias": "cheap" },
        "openrouter/deepseek/deepseek-v4-flash":   { "alias": "parallel" },  // [VERIFY slug]
        "openrouter/deepseek/deepseek-v3.2":       { "alias": "ds" },
        "openrouter/anthropic/claude-sonnet-4.6":  {
          "alias": "premium",
          "cacheRetention": "long"   // 1h TTL — экономия 90% на input при повторных вызовах
        },
        "openrouter/anthropic/claude-sonnet-4.5":  { "alias": "premium-prev" },
        "openrouter/anthropic/claude-haiku-4.5":   { "alias": "haiku" }
      },

      // === HEARTBEAT: фоновые проверки каждые 30 мин ===
      "heartbeat": {
        "every": "30m",
        "model": "openrouter/google/gemini-2.5-flash-lite",
        "target": "last",
        "isolatedSession": false   // важно: см. issue #19445
      },

      // === SUBAGENTS: параллельные задачи (поиск, парсинг, мелкие правки) ===
      "subagents": {
        "model": "openrouter/deepseek/deepseek-v4-flash",  // [VERIFY slug]
        "maxConcurrent": 3,
        "archiveAfterMinutes": 60
      },

      // === IMAGE: vision-задачи (скрины, OCR) ===
      // Kimi K2.6 нативно мультимодален, можно оставить тот же primary,
      // но явное поле полезно для надёжности
      "imageModel": {
        "primary": "openrouter/moonshotai/kimi-k2.6",
        "fallbacks": ["openrouter/google/gemini-2.5-flash-lite"]
      },

      // === Контекстный лимит на сессию ===
      "contextTokens": 200000  // оставляем headroom; Kimi К2.5 имеет 262k
    }
  }
}
```

[VERIFY] поля выше:
- Точный slug **DeepSeek V4 Flash** на OpenRouter — модель вышла 24 апр 2026, slug может быть `deepseek/deepseek-v4-flash`, либо `deepseek/deepseek-chat-v4-flash`. Проверь через `openclaw models scan --provider deepseek` или на openrouter.ai/deepseek.
- Поле `cacheRetention: "long"` — описано в feature request issue #17112 в репо openclaw/openclaw, статус интеграции в стабильную ветку проверь через `openclaw update --channel stable` и changelog.
- Поведение `auth.profiles` для двух ключей с автоматическим переключением — задокументировано в `/providers/openrouter`, но детали fallback'а между профилями стоит протестировать руками.

### Шаг 4. Запуск daemon и тест

```bash
# Установить config (если правил вручную — перезагрузи)
openclaw config reload   # [VERIFY: команда не явно подтверждена в docs, альтернатива — рестарт daemon]

# Перезапустить daemon
openclaw daemon restart

# Тестовый вызов — встроенный probe моделей
openclaw models test       # [VERIFY: точное имя команды; в docs встречается `openclaw models scan` для списка]
# Альтернативно:
openclaw models scan --set-default openrouter/moonshotai/kimi-k2.6

# Проверить статус
openclaw gateway status

# Послать тестовое сообщение
openclaw chat "Привет! Какая ты модель и какой у тебя контекст?"
```

### Шаг 5. Опционально — BYOK для Anthropic (если уже есть прямой ключ)

```bash
# 1. https://openrouter.ai → Settings → Integrations → BYOK → Add provider
# 2. Выбрать Anthropic, вставить sk-ant-...
# 3. Готово — теперь openrouter/anthropic/* идут твоим ключом, бесплатно до 1M req/мес
```

---

## ⚠️ Подводные камни

1. **Spending cap $2/день — это hard limit, не soft.** Запросы после исчерпания возвращают **HTTP 402 Payment Required**, OpenClaw фолбэк не подхватит (фолбэки срабатывают на 429/5xx). Решение — два API-ключа (см. лайфхак #7) **или** просто подними cap до $5–10 и расслабься.

2. **Heartbeat игнорирует свой `model`-override** при `isolatedSession: true` (issue #19445). Симптом: ты прописал Flash-Lite, а billing показывает heartbeat'ы на Kimi. Workaround — `isolatedSession: false` или совсем не выставлять поле.

3. **Subagents иногда «прорываются» на primary** (issue #47358). Ставь `agents.defaults.subagents.model` обязательно явно, плюс по возможности продублируй на уровне конкретного агента (`agents.list[].subagents.model`).

4. **Anthropic prompt caching ломается** при динамическом контенте в системном промпте (timestamps, session-id, текущая дата). Cache работает на **точное побайтовое совпадение префикса**. Решение — все динамические переменные выноси из системного промпта в первое user-сообщение, либо в отдельный `<runtime>` блок после стабильного куска SOUL.md.

5. **`openrouter/auto` непредсказуем по цене.** Удобно как fallback на heartbeat, но не как primary — он может неожиданно отправить твой запрос на дорогую модель, если посчитает задачу «сложной». Для prod — явный список моделей.

6. **Контекст vs контекст-биллинг.** OpenRouter тарифицирует **по input-токенам, включая системный промпт + всю историю**. На длинной сессии 100k+ токенов история становится дороже самого ответа. Используй `compaction` в OpenClaw (если поддержан) или ручной `/clear`.

7. **Kimi K2.6 vs K2.5 — разница в цене 1.7×, в качестве небольшая.** Если бюджет жмёт — оставь K2.5 как primary, K2.6 не нужен большинству юзеров.

8. **Reasoning-модели жрут output-токены.** DeepSeek-Reasoner возвращает full reasoning trace в outputs — биллится. Включай только осознанно, под конкретную задачу.

9. **Tier-A модели (Kimi K2.6 за $0.30/run против Opus за $0.63/run на похожей задаче) — это «достаточно умно», не «топ»**. На простом коде Kimi в сравнениях иногда обгоняет Opus, на сложной архитектуре — отстаёт. Не делай Kimi premium — для важного держи Sonnet 4.6.

10. **OpenRouter attribution headers (HTTP-Referer, X-OpenRouter-Title)** добавляются автоматически OpenClaw'ом. На анонимные/прокси-эндпоинты не отправляются. Это нормально, не фикси.

11. **`model.fallbacks` срабатывает только на ОШИБКАХ провайдера**, не на «модель ответила плохо». Не ожидай, что фолбэк автоматически переключит на Sonnet, если Kimi даёт чушь — это надо ловить руками или через subagent-валидатор.

12. **Vision стоит больше за изображения, чем за текст.** Kimi K2.5/K2.6 нативно мультимодальны, изображение тарифицируется как ~1500 токенов input. На 100 скринов в день это $0.07 — копейки, но мониторь.

---

## ✅ Чек-лист выполнения

- [ ] Создан аккаунт на openrouter.ai (OAuth через Google/GitHub)
- [ ] Пополнено $10 (Settings → Credits → Add Credits)
- [ ] Создан API-ключ `openclaw-primary` с **Credit Limit $2.00, Reset Daily**
- [ ] (Опционально) Создан резервный ключ `openclaw-emergency` с cap $5, без reset
- [ ] (Опционально) Настроен BYOK для Anthropic в OpenRouter Settings → Integrations
- [ ] API-ключ установлен через `openclaw onboard --auth-choice openrouter-api-key` или env-переменную `OPENROUTER_API_KEY`
- [ ] Файл `~/.openclaw/openclaw.json` отредактирован: `agents.defaults.model.primary`, `.fallbacks`, `.heartbeat.model`, `.subagents.model`
- [ ] Прописаны алиасы в `agents.defaults.models` (primary / cheap / parallel / premium)
- [ ] Включён `cacheRetention: "long"` на Anthropic-моделях
- [ ] Поставлено `heartbeat.isolatedSession: false` (workaround issue #19445)
- [ ] Demon перезапущен: `openclaw daemon restart`
- [ ] `openclaw gateway status` → green
- [ ] `openclaw models test` (или `openclaw models scan`) → все 4 модели каскада отвечают
- [ ] Тестовое сообщение в чат — отвечает primary (Kimi K2.6 или K2.5)
- [ ] `/model premium` переключает на Claude Sonnet 4.6, ответ заметно «жирнее»
- [ ] `/model cheap` переключает на Gemini Flash-Lite — ответы быстрые и копеечные
- [ ] В OpenRouter dashboard → Activity видны запросы с правильными моделями
- [ ] Записал в personal-notes какая модель тебе субъективно понравилась

---

## 🧪 Верификация

### Тест 1. Каскад работает по уровням
```bash
openclaw chat "Hi"
# → должна ответить Kimi K2.6 (primary). Проверь model в OpenRouter Activity.
```

### Тест 2. Heartbeat бьёт в Flash-Lite
```bash
# Подождать 30 минут, либо принудительно:
openclaw heartbeat trigger   # [VERIFY: команда]
# В OpenRouter Activity должна появиться запись с моделью google/gemini-2.5-flash-lite
```

### Тест 3. Subagent уходит в DeepSeek
```bash
openclaw chat "Найди в моих заметках все упоминания OpenClaw и перечисли их"
# → primary спавнит subagent для поиска. В Activity увидишь запрос на deepseek/deepseek-v4-flash.
```

### Тест 4. Premium через alias
```bash
openclaw chat "/model premium Спроектируй мне архитектуру multi-tenant SaaS на FastAPI"
# → ответ от claude-sonnet-4.6, длинный, развёрнутый.
```

### Тест 5. Fallback срабатывает
```bash
# Временно сломай primary — поставь несуществующий model ID и пошли запрос.
# Должен подхватить первый fallback (Kimi K2.5).
# Не забудь вернуть рабочий primary.
```

### Тест 6. Spending cap работает
```bash
# Не специально — отслеживай в OpenRouter Activity. Если в течение дня крутишь много —
# к концу дня посмотри: при подходе к $2 запросы должны начать возвращать 402.
```

---

## ⏱ Реальная оценка времени

| Подэтап | Оценка |
|---|---|
| Регистрация на OpenRouter + пополнение $10 (с банковской картой) | 5–10 мин |
| Создание API-ключей с правильными caps | 3 мин |
| `openclaw onboard --auth-choice openrouter-api-key` | 2 мин |
| Ручное редактирование `openclaw.json` (+ выяснение точного slug DeepSeek V4 Flash) | 10–15 мин |
| Restart daemon + первый тест | 3 мин |
| Прогон 6 тестов из секции «Верификация» | 10–15 мин |
| Если упал — копание в логах, github issues, документации | +15–30 мин |
| **Итого реалистично** | **35–50 минут** при первом разу, **15 минут** при повторе |

Дмитрий заложил 30 минут — этого хватает только если OpenRouter регистрация прошла без kyc и onboard wizard не споткнулся. Закладывай 45 минут.

---

## 🔗 Связи с другими блоками

- **Блок 2 (Установка OpenClaw)** — должен быть завершён, daemon должен работать. Без этого `openclaw onboard` не запустится.
- **Блок 4 (Telegram)** — там используется per-channel model override (`telegram.agents.defaults.model.primary`). Можно для Telegram поставить **более дешёвую** модель (Kimi K2.5 / Haiku), чтобы лимит выбирался медленнее на чатах.
- **Блок 5 (Личность / SOUL.md)** — системный промпт сюда. Делай его **стабильным по-байтам** (без таймстампов, без uid'ов) — это включит prompt caching.
- **Блок 6 (Память)** — длинная память в context = большие input-биллинги. Рассмотри vector-retrieval вместо «вся память в системном промпте».
- **Блок 11 (Безопасность)** — API-ключи в env/keychain, не коммить `openclaw.json` с реальным ключом. В `.gitignore` обязательно `~/.openclaw/`.
- **Блок 12 (Проактивность)** — heartbeat-агенты, scheduled tasks работают на heartbeat-модели. Если их много — пересчитай дневные затраты на Flash-Lite.
- **Блок 13 (Дашборд)** — туда можно вывести live-стату из OpenRouter `/api/v1/key` (limit, limit_remaining) — полезно видеть остаток.

---

## 📚 Источники

**OpenClaw:**
- [docs.openclaw.ai/models](https://docs.openclaw.ai/models) — конфиг-поля `agents.defaults.model.primary/fallbacks`, `imageModel`, `models`-каталог
- [docs.openclaw.ai/providers/openrouter](https://docs.openclaw.ai/providers/openrouter) — точная схема BYOK для OpenRouter, env-переменные
- [docs.openclaw.ai/tools/subagents](https://docs.openclaw.ai/tools/subagents) — `agents.defaults.subagents.model`, приоритеты
- [docs.openclaw.ai/getting-started](https://docs.openclaw.ai/getting-started) — onboarding wizard, `--install-daemon`
- [GitHub openclaw/openclaw issue #19445](https://github.com/openclaw/openclaw/issues/19445) — баг с heartbeat isolatedSession
- [GitHub openclaw/openclaw issue #47358](https://github.com/openclaw/openclaw/issues/47358) — баг с subagent fallback на primary
- [GitHub openclaw/openclaw issue #17112](https://github.com/openclaw/openclaw/issues/17112) — feature request `cacheRetention`
- [velvetshark.com/openclaw-multi-model-routing](https://velvetshark.com/openclaw-multi-model-routing) — реальный пример каскада 50–80% экономии
- [openrouter.ai/docs/guides/coding-agents/openclaw-integration](https://openrouter.ai/docs/guides/coding-agents/openclaw-integration) — официальный гайд OpenRouter × OpenClaw

**OpenRouter:**
- [openrouter.ai/docs/guides/best-practices/prompt-caching](https://openrouter.ai/docs/guides/best-practices/prompt-caching) — implicit/explicit, минимальные токены, цены кэша
- [openrouter.ai/docs/guides/routing/model-fallbacks](https://openrouter.ai/docs/guides/routing/model-fallbacks) — синтаксис fallback chain
- [openrouter.ai/docs/guides/overview/auth/byok](https://openrouter.ai/docs/guides/overview/auth/byok) — BYOK setup
- [openrouter.ai/docs/api/reference/limits](https://openrouter.ai/docs/api/reference/limits) — credit limits, rate limits
- [openrouter.ai/docs/guides/features/guardrails](https://openrouter.ai/docs/guides/features/guardrails) — spending caps, guardrails
- [openrouter.ai/announcements/1-million-free-byok-requests-per-month](https://openrouter.ai/announcements/1-million-free-byok-requests-per-month) — 1M бесплатных BYOK

**Модели (страницы продуктов):**
- [openrouter.ai/moonshotai/kimi-k2.5](https://openrouter.ai/moonshotai/kimi-k2.5) — $0.44/$2.00, 262k context, релиз 27 янв 2026
- [openrouter.ai/moonshotai/kimi-k2.6](https://openrouter.ai/moonshotai/kimi-k2.6) — $0.7448/$4.655, intel 54
- [openrouter.ai/google/gemini-2.5-flash-lite](https://openrouter.ai/google/gemini-2.5-flash-lite) — $0.10/$0.40, 1M context
- [openrouter.ai/deepseek/deepseek-v4-pro](https://openrouter.ai/deepseek/deepseek-v4-pro) — V4 Pro $0.435/$0.87, релиз 24 апр 2026
- [openrouter.ai/anthropic/claude-sonnet-4.6](https://openrouter.ai/anthropic/claude-sonnet-4.6) — $3/$15, 1M context
- [openrouter.ai/anthropic/claude-sonnet-4.5](https://openrouter.ai/anthropic/claude-sonnet-4.5) — $3/$15, 1M context

**Бенчмарки:**
- [artificialanalysis.ai](https://artificialanalysis.ai) — Intelligence Index, output speed, cost
- [akitaonrails.com/en/2026/04/24/llm-benchmarks-parte-3-deepseek-kimi-mimo](https://akitaonrails.com/en/2026/04/24/llm-benchmarks-parte-3-deepseek-kimi-mimo/) — coding benchmark апрель 2026
- [vellum.ai/llm-leaderboard](https://www.vellum.ai/llm-leaderboard) — общий leaderboard
- [benchlm.ai/llm-agent-benchmarks](https://benchlm.ai/llm-agent-benchmarks) — tool use / function calling

**Альтернативы и фон:**
- [infrabase.ai/blog/ai-inference-providers-compared](https://infrabase.ai/blog/ai-inference-providers-compared) — сравнение провайдеров инференса
- [apiscout.dev/guides/fireworks-ai-vs-together-ai-vs-groq-inference-apis-2026](https://apiscout.dev/guides/fireworks-ai-vs-together-ai-vs-groq-inference-apis-2026) — Groq/Fireworks/Together
- [simonwillison.net/2026/Apr/24/deepseek-v4](https://simonwillison.net/2026/Apr/24/deepseek-v4/) — обзор DeepSeek V4 от Simon Willison
- [evolink.ai/blog/openclaw-claude-api-cost-reduction-guide-2026](https://evolink.ai/blog/openclaw-claude-api-cost-reduction-guide-2026) — частный гайд по cost reduction
