# Стандарт готовности — Воркшоп 2

> Версия: v1.1 (2026-05-12). Добавлены C.17 (Memory Search Protocol), D.4 (trajectory.jsonl-проверка), E.15 (autocommit whitelist), F.5 (watchdog `*/15`) — после полевых отчётов когорты Nov-2026.
> Что должно быть настроено у участника после Воркшопа 2.
> Это **источник истины** — все промпты ссылаются на этот документ.
> AI-исполнитель и аудитор используют его как чек-лист.

---

## Легенда

- ❗ **Критично** — без этого В2 не пройден, нужно доделать
- ⚠️ **Рекомендуется** — лучше сделать, но не блокер
- 💡 **Опционально** — фича для продвинутых / для В3

---

## ⚠️ Стек моделей В2 — БЕЗ Anthropic напрямую

После закрытия Anthropic Max OAuth для third-party tools (4 апреля 2026) у нас **нет прямого доступа** к Anthropic. Все Haiku-модели идут через **OpenRouter** или заменяются эквивалентами из нашего каскада В1.

**Каскад моделей В2 наследуется из стандарта В1 без изменений** — см. `workshop-1-standard.md` раздел C (Primary, Fallback, Premium, Heartbeat, Subagents, Image). Не дублируем slugs здесь, чтобы при обновлении не возникало расхождений.

**Дополнительные роли в В2:**
- **Compaction summarizer** (сжимает середину диалога): `openrouter/moonshotai/kimi-k2.6` (мультиязычный, дёшево). Альтернатива через OpenRouter: `openrouter/anthropic/claude-haiku-4.5` если slug живой.
- **memoryFlush model** (записывает важное перед сжатием): тот же — `openrouter/moonshotai/kimi-k2.6`.
- **LLM-classifier для privacy guard** (определяет секреты): `openrouter/google/gemini-2.5-flash-lite` (самый дешёвый из стека).
- **Embeddings** (векторизация для Mem0/Qdrant): `text-embedding-3-small` через **openai** профиль (~$1/мес) или локальный `bge-m3` если хочешь приватности.
- **Reranker** (отбор top-N после hybrid search): локальный `bge-reranker-v2-m3` (multilingual) — без API-ключа.

**Anthropic-модели в схеме конфигов прямо НЕ упоминаются.** Если нужен Claude — только через OpenRouter с явным префиксом `openrouter/anthropic/`.

---

## A. Архитектура памяти — workspace files

| # | Критерий | Уровень |
|---|---|---|
| A.1 | Трёхуровневая архитектура файлов: личность (SOUL.md, USER.md, IDENTITY.md) ≠ операции (AGENTS.md, TOOLS.md, HEARTBEAT.md) ≠ знания (MEMORY.md, memory/) | ❗ |
| A.2 | `MEMORY.md` создан с 5 жёсткими секциями: 👤 Предпочтения / 🏢 Активные клиенты / 🔑 Ключевые решения / 📇 Контакты / 📚 Фреймворки | ❗ |
| A.3 | Файл MEMORY.md ≤200 строк (он инжектится в каждую сессию — большой съест токены) | ⚠️ |
| A.4 | Папка `~/.openclaw/workspace/memory/` создана + шаблон `_template.md` | ❗ |
| A.5 | Файл сегодняшнего дня `memory/$(date +%Y-%m-%d).md` существует | ⚠️ |
| A.6 | Нет дублирующих memory-плагинов: `openclaw skills list \| grep -iE "mem\|memory"` ≤2 строки | ❗ |
| A.7 | MEMORY.md инжектится в системный промпт ОДИН раз при старте сессии (не каждое сообщение) | ⚠️ |

---

## B. Защита контекста (compaction + pruning)

| # | Критерий | Уровень |
|---|---|---|
| B.1 | `agents.defaults.compaction.enabled: true` | ❗ |
| B.2 | `agents.defaults.compaction.softThresholdTokens: 40000` (НЕ 4000 — иначе важное теряется) | ❗ |
| B.3 | `agents.defaults.compaction.hardThresholdTokens: 80000` | ❗ |
| B.4 | `agents.defaults.compaction.strategy: "summarize-middle"` | ❗ |
| B.5 | `agents.defaults.compaction.summarizerModel: "openrouter/moonshotai/kimi-k2.6"` | ❗ |
| B.6 | `preserveTags: ["decision", "fact", "action-required"]` | ⚠️ |
| B.7 | `agents.defaults.compaction.memoryFlush.enabled: true` (с мониторингом issue #54408) | ⚠️ |
| B.8 | `agents.defaults.compaction.memoryFlush.model: "openrouter/moonshotai/kimi-k2.6"` | ⚠️ |
| B.9 | `agents.defaults.contextPruning.mode: "cache-ttl"` (без этого через 2 недели бот молча перестанет отвечать) | ❗ |
| B.10 | `agents.defaults.contextInjection: "continuation-skip"` (экономия 8–12k токенов на длинных диалогах) | ⚠️ |
| B.11 | Тест: 3 сообщения подряд с фактом в первом — бот помнит факт в третьем | ⚠️ |

---

## C. Постоянная память — Qdrant + Mem0

| # | Критерий | Уровень |
|---|---|---|
| C.1 | Qdrant запущен в Docker: `docker compose ps` → `healthy` | ❗ |
| C.2 | Версия зафиксирована: `qdrant/qdrant:v1.12.4` (НЕ `:latest` — иначе при автоапдейте сломается формат индексов) | ❗ |
| C.3 | Порты ТОЛЬКО на loopback: `ss -tlnp \| grep 6333` → `127.0.0.1:6333`. Никакого `0.0.0.0`! | ❗ |
| C.4 | `restart: unless-stopped` + healthcheck в docker-compose | ⚠️ |
| C.5 | Mem0 SDK подключён: `openclaw skills list \| grep mem0` → active | ❗ |
| C.6 | Vector store настроен: `vector_store: qdrant://127.0.0.1:6333`, collection `openclaw_main` | ❗ |
| C.7 | Embedder: `text-embedding-3-small` (OpenAI) ИЛИ локальный `bge-m3` через Ollama | ❗ |
| C.8 | Hybrid search активен: `vectorWeight: 0.7`, `textWeight: 0.3` (BM25), `candidateMultiplier: 4` | ❗ |
| C.9 | MMR включён: `lambda: 0.7` | ⚠️ |
| C.10 | TemporalDecay: `halfLifeDays: 30` (свежее весит больше) | ⚠️ |
| C.11 | Reranker: `bge-reranker-v2-m3` (multilingual, локально) или Cohere v3 | ⚠️ |
| C.12 | Auto-capture включён: `autoCapture: true`, `dedupe_threshold: 0.92` | ❗ |
| C.13 | Privacy guard: `detect-secrets` v1.5+ установлен | ❗ |
| C.14 | Privacy guard pre-write hook блокирует регексы (sk-/ghp-/AKIA/JWT/password/СНИЛС/ИНН/credit card) | ❗ |
| C.15 | Privacy guard fallback LLM-classifier на `openrouter/google/gemini-2.5-flash-lite` (только если regex не сработал) | ⚠️ |
| C.16 | `blockOnDetect: true` — пароли/токены БЛОКИРУЮТСЯ на запись (НЕ маскируются) | ❗ |
| C.17 | **Memory Search Protocol** — в `workspace/AGENTS.md` обязательная секция «звать memory_search/mem0-search перед фактологическими ответами». Дублирующий буллет в SOUL.md. Без этого LLM не зовёт mem0-skill, идёт в web_search и фабрикует — D.2 проходит формально через injection. | ❗ |

---

## D. Финальный тест памяти — auto-capture + amnesia + tool_call

| # | Критерий | Уровень |
|---|---|---|
| D.1 | Auto-capture тест (5 минут): после 3 любых фактов в Telegram бот помнит их без команды «запомни». Факты выбирает участник сам — не хардкод. | ❗ |
| D.2 | Amnesia test: после `/reset` → вопросы по тем же 3 фактам → бот отвечает по сути из Qdrant | ❗ |
| D.3 | Бонус-домашка через 4 часа: те же 3 факта проверяются повторно — бот помнит после паузы | ⚠️ |
| D.4 | **Trajectory tool_call check**: в `agents/main/sessions/<id>.trajectory.jsonl` на каждый D.1/D.2/D.3 вопрос есть `tool_call: memory_search` или `exec → mem0-search.js`. Если 0 calls — D НЕ ПРОЙДЕН независимо от точности ответа (бот мог взять из startupContext, не из retrieval). Команда: `tail -200 ~/.openclaw/agents/main/sessions/$(ls -t ~/.openclaw/agents/main/sessions/ \| head -1)/trajectory.jsonl \| grep -cE "memory_search\|mem0-search"` ≥ 3. | ❗ |

---

## E. Бэкап на GitHub

| # | Критерий | Уровень |
|---|---|---|
| E.1 | Приватный GitHub-репо для `~/.openclaw/`: `gh repo view --json visibility` → `PRIVATE` | ❗ |
| E.2 | `.gitignore` включает: `openclaw.json`, `*.token`, `*.key`, `secrets/**`, `.env`, `qdrant/storage/**`, `tmp/`, `logs/`, `*.ogg`, `agents/*/sessions/cache/` | ❗ |
| E.3 | Только один коммит до настройки git-crypt (не успели запушить токены в plaintext) | ❗ |
| E.4 | `git-crypt init` выполнен | ❗ |
| E.5 | `.gitattributes` шифрует: `openclaw.json`, `*.token`, `secrets/**`, `.env` | ❗ |
| E.6 | `git-crypt status` → `openclaw.json: encrypted: YES` | ❗ |
| E.7 | Ключ git-crypt сохранён в **менеджере паролей с облачной синхронизацией** (1Password / Apple Keychain / Bitwarden / KeePass) | ❗ |
| E.8 | `gitleaks` pre-commit hook установлен | ❗ |
| E.9 | GitHub Push Protection включён в Settings репо → Code security → Secret scanning | ❗ |
| E.10 | Cron автокоммит: `crontab -l \| grep openclaw-autocommit` показывает `0 * * * *` с `flock` | ❗ |
| E.11 | Коммиты идут в ветку `auto/cron`, не в `main` | ⚠️ |
| E.12 | Через 1 час после установки cron: `git log --oneline auto/cron \| head -3` → есть свежий auto-commit | ❗ |
| E.13 | Daily merge `auto/cron → main` --squash в 23:00 | ⚠️ |
| E.14 | `RECOVERY.md` написан с 3 сценариями (VPS сгорел / ключ потерян / бот не отвечает) | ⚠️ |
| E.15 | **Autocommit whitelist** — `~/.openclaw/scripts/openclaw-autocommit.sh` использует ЯВНЫЙ список путей (`stage_workspace_if_exists`), НЕ `git add .` / `git add -A`. Blocklist для `openclaw.json`, `auth-profiles.json`, `secrets/**`, `.env`, `*.token`, `*.key` — abort если попали в индекс. Защита от утечки `agents/main/agent/auth-profiles.json` с plaintext API-ключами. | ❗ |

---

## F. Гигиена памяти + permission watchdog

| # | Критерий | Уровень |
|---|---|---|
| F.1 | `archive-memory.sh` — заметки memory/ старше 30 дней → `archive/`, cron `0 3 * * 0` (воскресенье 3:00) | ⚠️ |
| F.2 | `memorySearch.paths` включает `archive/` (старое не выпадает из поиска) | ⚠️ |
| F.3 | Weekly digest cron `0 10 * * 1` (понедельник 10:00 МСК) — Kimi читает 7 дней memory/ → дописывает в MEMORY.md | ⚠️ |
| F.4 | `pre-update-backup.sh` — tar+gpg всей `~/.openclaw/` + Qdrant snapshot перед каждым `openclaw update` | ⚠️ |
| F.5 | **Permission-watchdog cron `*/15 * * * *`** (не `17 4 * * *` раз в сутки!) — каждые 15 мин проверяет `chmod 600` на openclaw.json/SOUL.md/auth-profiles.json/secrets/. При 644 → auto-chmod + Telegram alert. Drift-окно ≤15 мин вместо 24h. Защита от регрессии #18866 после случайного `doctor --fix`. | ❗ |

---

## G. Доделки В1 (закрыть в начале В2)

| # | Критерий | Уровень |
|---|---|---|
| G.1 | Heartbeat реально работает на дешёвой модели: `openclaw logs --grep heartbeat --tail 30` показывает `gemini-2.5-flash-lite`, не primary (баг #30894) | ❗ |
| G.2 | Prompt caching включён для применимых моделей; cache hit rate ≥60% после прогрева (5 одинаковых запросов) | ⚠️ |
| G.3 | В системных промптах (SOUL.md/USER.md/IDENTITY.md) НЕТ динамических timestamps вида `YYYY-MM-DD` (например `2026-05-08`) — они инвалидируют кэш каждый ход | ❗ |
| G.4 | `chmod 600 ~/.openclaw/openclaw.json` после каждого `doctor --fix` (баг #18866) | ❗ |
| G.5 | Watchdog проверяет права openclaw.json каждый день — при 644 alert + auto-chmod | ⚠️ |
| G.6 | Привычка: после правки openclaw.json → `openclaw doctor --fix && openclaw gateway restart && chmod 600 openclaw.json`. Hot-reload молча НЕ работает для compaction. | ❗ |
| G.7 | Команды `/context list` и `/usage full` работают в Telegram | ⚠️ |
| G.8 | Slugs моделей сверены с актуальным OpenRouter (`curl https://openrouter.ai/api/v1/models`) — нет устаревших | ❗ |
| G.9 | `ackReaction: "👀"` настроен в Telegram channel | 💡 |

---

## H. Обещания НА В3 (НЕ В2)

То что мы НЕ делаем в В2 — переносим явно:

- **TTS (голос)** — попробовали в В1 как ⚠️ G.1 (модель `tts-1` voice `alloy`), в В2 не дошло из-за качества русского у дешёвых OpenAI-моделей. Переносим в В3 как опциональный апгрейд через ElevenLabs / Yandex SpeechKit / локальный edge-tts.
- **Whisper транскрипция входящих голосовых** — отложено с В1 (G.3 💡).
- **Heartbeat-сценарии (утренний брифинг и т.п.)** — В3 «Проактивность».
- **Skills из ClawHub (calendar, gmail)** — В3.
- **Multi-agent + n8n** — В4.
- **Obsidian + Syncthing** — оставляем опц в В2 для тех у кого Obsidian уже есть (раздел E с git-репо vault'a). Но не критично.

---

## Финальный итог

После Воркшопа 2 **минимум** должен быть закрыт каждый ❗ критерий разделов A–E (память + защита контекста + Qdrant/Mem0 + бэкап) + критичные доделки В1: **G.1, G.3, G.4, G.6, G.8** (heartbeat-модель, нет timestamps в SOUL, chmod 600, привычка restart, сверка моделей).

**Зачёт В2:** все ❗ закрыты И:
- Amnesia test пройден (D.2)
- Cron автокоммит реально создаёт коммиты (E.12)
- В реальном диалоге с ботом память работает (D.1)

⚠️ — желательно закрыть к Воркшопу 3, не блокирует.
💡 — фичи будущего, post-sprint материал.

---

## Известные ограничения OpenClaw 2026.4.x

Те же что в standards/workshop-1-standard.md:
- ❌ `auth.profiles` в openclaw.json → CLI
- ❌ `voice.transcription` → схема другая, отложено
- ❌ `spending` config caps → не применяется
- ❌ `premiumGuard` → не применяется
- ❌ `heartbeat.rateLimit` / `skipWhenBusy` / `fallbacks` → не поддерживается
- ⚠️ Issue #54408 — `memoryFlush` иногда «протекает» в основную сессию. При обнаружении — отключи `memoryFlush.enabled: false`, потеря только B.7/B.8.
- ⚠️ Issue #74813 — `continuation-skip` иногда ломается после compaction. Симптом: бот забывает контекст внутри одной сессии. Fallback: переключи `contextInjection: "always"`.
- ⚠️ Issue #18866 — `doctor --fix` сбрасывает права на 644. Всегда после `chmod 600`. **F.5 watchdog ловит это каждые 15 мин.**
- ⚠️ Issue #30894 — `heartbeat.model` иногда молча игнорится. Проверка через логи.
- ⚠️ Issue #4645 — OpenClaw ≥2026.5.0 ужесточил dangerous-code-detection. Mem0 SDK install (паттерн «env vars + outbound network») требует флаг `--dangerously-force-unsafe-install`. Это known compat-shift, не баг.

### MiniMax M2.7 — поведенческая особенность

MiniMax по характеру выводит chain-of-thought наружу и повторяет вопрос пользователя. Это **не баг конфига** — лечится только агрессивным SOUL.md (anti-verbosity секция). Если после правил SOUL.md модель продолжает болтать — рассмотри переключение primary на `openrouter/anthropic/claude-haiku-4.5` (платно токенами, но чистый вывод) или на DeepSeek (если есть подписка).

---

## Что ОТСУТСТВУЕТ в стандарте (зафиксировано чтобы не путаться)

- **TTS-провайдер ElevenLabs** — не входит в В2.
- **Anthropic API direct** — недоступен (Max ban). Только через OpenRouter.
- **Obsidian как обязательный слой памяти** — опционально; без него все 4 ❗ из C закрываются.
- **Yandex SpeechKit / edge-tts** — не входит в В2 (это В3 «Голос»).
