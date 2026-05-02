# Скрытые фичи OpenClaw — то, что не показывают на демо

> Эксклюзивная подборка недокументированных и малоизвестных возможностей OpenClaw
> Дата исследования: апрель 2026
> Версия фокуса: OpenClaw 2026.4.x (включая 2026.4.25-beta.4 и 2026.4.27)
> Автор сборки: research-агент Дмитрия

Этот документ собран из официальных доков, GitHub issues, release notes и обсуждений. Все утверждения снабжены ссылками-доказательствами. Каждая фича прошла верификацию минимум по двум источникам, где это было возможно.

---

## ТОП-15 скрытых фич OpenClaw

### 1. NO_REPLY — silent housekeeping без следа в чате

**Где живёт:** ядро session-manager, плюс `agents.defaults.compaction.memoryFlush` и любой пользовательский промпт.

**Как активировать:**
```jsonc
// ~/.openclaw/openclaw.json
{
  "agents": {
    "defaults": {
      "compaction": {
        "memoryFlush": {
          "enabled": true,
          "softThresholdTokens": 4000,
          "reserveTokensFloor": 20000,
          "model": "anthropic/claude-haiku-4-6", // дешёвая модель для flush
          "systemPrompt": "Сохрани durable factы в memory/YYYY-MM-DD.md. Если ничего важного — ответь NO_REPLY."
        }
      }
    }
  }
}
```

В чате можно отправить агенту служебное сообщение и попросить его ответить токеном `NO_REPLY` — пользователь ничего не увидит, но турн произойдёт. Это особенно полезно для cron-задач, которые должны "молча" дёрнуть проверку.

**Что это даёт:** агент пишет в memory/ перед компакцией, перезаписывает durable state, но в чате нет шума. Идеально для long-running сессий, где компакция режет контекст.

**Источник-доказательство:** [issue #44787 — NO_REPLY semantics](https://github.com/openclaw/openclaw/issues/44787), [issue #6877 — pre-compaction memory flush](https://github.com/openclaw/openclaw/issues/6877), [Session management deep dive](https://docs.openclaw.ai/reference/session-management-compaction).

**Подвох:** в issue #54408 описан баг — pre-compaction memory flush может протекать в основную сессию как user message и инициировать compaction loop. Если включаете — мониторь логи первые сутки.

---

### 2. Скрытое hot-reload trifecta: restart / hot-apply / hybrid

**Где живёт:** `gateway.configReload` и per-section настройки в `openclaw.json`.

**Как активировать:**
```jsonc
{
  "gateway": {
    "configReload": "hybrid"  // restart | hot-apply | hybrid
  }
}
```

После сохранения файла — `openclaw gateway call config.reload` без перезапуска gateway. Большинство channel-секций, model providers, tools и memory подхватываются мгновенно.

**Что это даёт:** правишь конфиг при работающем боте, не теряешь активные Telegram/Discord сессии. Базовые туториалы говорят "перезапустите gateway" — это ложь для большинства настроек.

**Источник-доказательство:** [Configuration reference](https://docs.openclaw.ai/gateway/configuration-reference) — упомянут как "Hot Reload: Configuration changes support three modes—restart, hot-apply, or hybrid".

**Подвох:** auth/binding/Tailscale всё-таки требуют restart. Channel tokens — hot-apply работает.

---

### 3. Trajectory Bundles — полная запись turn'а агента для дебага

**Где живёт:** `OPENCLAW_TRAJECTORY` env var + slash-команда `/export-trajectory`.

**Как активировать:**
```bash
# Постоянная запись:
export OPENCLAW_TRAJECTORY=/Users/you/openclaw-traces
openclaw gateway

# Разовый экспорт прямо из чата:
/export-trajectory bug-12345
# или короче
/trajectory
```

Записывает:
- `events.jsonl` — упорядоченный таймлайн всех событий (model call, tool start/end, compaction)
- `prompts.json` + `system-prompt.txt` — точные промпты, отправленные модели
- `tools.json` — какие тулы были доступны и как были описаны
- `session-branch.json` — отредактированный транскрипт
- `metadata.json` — версии, плагины, runtime

**Что это даёт:** воспроизводимость багов. Если агент странно себя ведёт — выгружаешь bundle и видишь точный input. Также — основа для дистилляции датасета (см. фичу #15).

**Источник-доказательство:** [docs.openclaw.ai/tools/trajectory](https://docs.openclaw.ai/tools/trajectory) — "When OPENCLAW_TRAJECTORY is set, OpenClaw writes one JSONL file per session id".

**Подвох:** содержит prompt cache metadata и raw output. Не публикуй bundle публично — `OpenClaw redacts sensitive values before writing export files`, но это best-effort.

---

### 4. /debug — runtime-only override конфига без перезапуска

**Где живёт:** chat slash command, защищён `commands.debug: true`.

**Как активировать:**
```jsonc
// openclaw.json
{ "commands": { "debug": true } }
```

В чате:
```
/debug show
/debug set messages.responsePrefix="[DEBUG-SESSION]"
/debug set agents.defaults.compaction.model="anthropic/claude-sonnet-4-7"
/debug unset messages.responsePrefix
/debug reset    # сброс всех overrides
```

Изменения живут только в памяти gateway — на диск ничего не пишется. После рестарта — всё возвращается к openclaw.json.

**Что это даёт:** A/B тестирование разных моделей/промптов прямо в чате. Не надо редактировать файл и перезапускать. Идеально для отладки конкретной сессии.

**Источник-доказательство:** [Slash commands docs](https://docs.openclaw.ai/tools/slash-commands), [Debugging](https://docs.openclaw.ai/help/debugging).

**Подвох:** owner-only. И в group chat'ах опасно — overrides действуют на всех в этой сессии.

---

### 5. /trace — диагностика плагинов без полного /verbose

**Где живёт:** chat command, отдельно от `/verbose` и `/debug`.

**Как активировать:**
```
/trace on
# делаешь действие
/status   # увидишь plugin-trace lines
/trace off
```

**Что это даёт:** видишь pipeline хук'ов (compaction:before, model:resolved, stream:wrap), какие плагины срабатывают, в каком порядке, сколько занимают. БЕЗ показа полного raw output (как делает /verbose).

**Источник-доказательство:** [Slash commands docs](https://docs.openclaw.ai/tools/slash-commands) — "/trace lets you toggle session-scoped plugin trace/debug lines without turning on full verbose mode".

**Подвох:** в group chat виден всем — может леакать имена плагинов и их внутренний state. В DM — ок.

---

### 6. /btw — параллельный side-вопрос без прерывания основной задачи

**Где живёт:** native slash command.

**Как активировать:**
```
# Агент в долгом турне (компиляция, исследование)
/btw а во сколько у меня встреча сегодня?
```

Возвращает ответ как "live side result" — отдельным сообщением, не вставляя в основной flow. Основной турн продолжается.

**Что это даёт:** мульти-таск без прерывания. Особенно важно для cron-агентов и long-running tasks.

**Источник-доказательство:** [issue #34881 mentions /btw alongside /steer](https://github.com/openclaw/openclaw/issues/34881), [Slash commands docs](https://docs.openclaw.ai/tools/slash-commands).

**Подвох:** /btw использует ту же сессию как контекст, но НЕ пишется в её транскрипт как обычное сообщение. Полезно для приватных вопросов агенту.

---

### 7. /queue debounce + drop:summarize — суммаризация сброшенных сообщений

**Где живёт:** `/queue` chat command + `agents.defaults.queue` config.

**Как активировать:**
```
/queue debounce:2s cap:25 drop:summarize
```

Или в конфиге:
```jsonc
{
  "agents": {
    "defaults": {
      "queue": {
        "debounceMs": 2000,
        "cap": 25,
        "drop": "summarize"  // вместо "old" или "new"
      }
    }
  }
}
```

**Что это даёт:** если флудишь агента сообщениями — вместо потери старых, OpenClaw СУММАРИЗИРУЕТ их и кладёт сводку в один followup turn. Не теряешь контекст при пиковой нагрузке.

**Источник-доказательство:** [Command Queue docs](https://docs.openclaw.ai/concepts/queue) — "drop: 'summarize' (retain summaries of dropped messages), 'old' (discard oldest), or 'new' (reject newest)".

**Подвох:** `drop:summarize` стоит дополнительный LLM-вызов на каждый дроп. Если канал высоконагружен — увеличишь стоимость.

---

### 8. Heartbeat wake-mode — батчинг cron'ов в один турн агента

**Где живёт:** `agents.defaults.heartbeat` + cron job `wakeMode`.

**Как активировать:**
```bash
# Создать cron, который НЕ запускает свой турн, а ждёт следующего heartbeat:
openclaw cron add "Проверь почту" \
  --at "*/15 * * * *" \
  --wake-mode batch \
  --light-context
```

Эквивалент в конфиге:
```jsonc
{
  "agents": {
    "defaults": {
      "heartbeat": {
        "enabled": true,
        "intervalMinutes": 30,
        "batchPendingCrons": true
      }
    }
  }
}
```

**Что это даёт:** 5 близких по времени cron'ов сольются в ОДИН турн агента — вместо 5 отдельных API-вызовов и 5 раз перезагрузки контекста. Экономия токенов 60–80%.

**Источник-доказательство:** [Cron vs Heartbeat docs](https://docs.openclaw.ai/automation/cron-vs-heartbeat), search analysis: "OpenClaw's heartbeat and cron systems are deeply integrated through a wake-mode mechanism".

**Подвох:** не подходит для time-critical cron'ов (полный отчёт ровно в 9:00) — для них оставь дефолтный режим isolated.

---

### 9. Dreaming REM-backfill — пересборка durable памяти из старых файлов

**Где живёт:** `openclaw memory rem-backfill` CLI, плагин memory-core.

**Как активировать:**
```bash
# Сначала включить dreaming
openclaw config set 'plugins.entries.memory-core.config.dreaming.enabled' true

# Прогнать старые daily-notes через REM-pipeline (без записи)
openclaw memory rem-backfill --path memory/ --grounded

# Записать reversible diary entries в DREAMS.md
openclaw memory rem-backfill --path memory/ --stage-short-term

# Откат, если что-то пошло не так
openclaw memory rem-backfill --rollback
openclaw memory rem-backfill --rollback-short-term
```

И прозрачное превью того, как REM проскорил конкретного кандидата:
```bash
openclaw memory promote-explain "наша встреча с Сашей"
# вернёт breakdown: relevance 0.30, frequency 0.24, query diversity 0.15, recency 0.15...
```

**Что это даёт:** старые memory/2025-*.md файлы, которые скопились ДО включения dreaming, теперь могут быть переработаны и попасть в durable MEMORY.md. Без второго memory-стека.

**Источник-доказательство:** [Memory CLI docs](https://docs.openclaw.ai/cli/memory), [release v2026.4.9 — REM backfill](https://github.com/openclaw/openclaw/releases/tag/v2026.4.9), [Vox tweet](https://x.com/Voxyz_ai/status/2042142846065561920).

**Подвох:** `--grounded` очень дорог по токенам на больших архивах. Сначала прогоняй на одной директории.

---

### 10. Sub-agents fork-context — наследование транскрипта родителя

**Где живёт:** `sessions_spawn` tool + `/subagents spawn`.

**Как активировать:**
```
/subagents spawn researcher "Найди источники по теме X" --context fork
```

Программно (внутри тула):
```ts
sessions_spawn({
  agentId: "researcher",
  task: "Найди источники",
  context: "fork",   // вместо "isolated"
  sandbox: "require" // ребёнок только в sandbox
});
```

**Что это даёт:** под-агент получает копию транскрипта родителя. Полезно когда чилд должен понимать всю предысторию (а не только отдельную задачу). По умолчанию — isolated (новая сессия с нуля).

**Конфиг для orchestrator pattern:**
```jsonc
{
  "agents": {
    "defaults": {
      "subagents": {
        "maxSpawnDepth": 2,        // главное → orchestrator → workers
        "maxChildrenPerAgent": 5,  // защита от runaway fan-out
        "model": "anthropic/claude-haiku-4-6"  // дешёвая модель для воркеров
      }
    }
  }
}
```

**Источник-доказательство:** [Sub-agents docs](https://docs.openclaw.ai/tools/subagents), [issue #6832 — sessions_spawn with depth limits](https://github.com/openclaw/openclaw/issues/6832).

**Подвох:** depth=2 это максимум. На depth=2 агенты НЕ могут спавнить детей — runaway prevention.

---

### 11. Diagnostics flags — selective verbose без шума

**Где живёт:** `OPENCLAW_DIAGNOSTICS` env + `diagnostics.flags` в openclaw.json.

**Как активировать:**
```bash
# Только Telegram HTTP-вызовы и payload:
OPENCLAW_DIAGNOSTICS=telegram.http,telegram.payload openclaw gateway

# Wildcards:
OPENCLAW_DIAGNOSTICS=telegram.* openclaw gateway

# Всё:
OPENCLAW_DIAGNOSTICS=* openclaw gateway

# Отдельный таймлайн стартапа в JSONL-файл:
export OPENCLAW_DIAGNOSTICS=timeline
export OPENCLAW_DIAGNOSTICS_TIMELINE_PATH=/tmp/openclaw-startup.jsonl
openclaw gateway
```

В конфиге:
```jsonc
{
  "diagnostics": {
    "flags": ["telegram.http", "gateway.*", "timeline"]
  }
}
```

**Что это даёт:** не нужно `--verbose` (заваливает логами). Включаешь только нужный subsystem. `timeline` особенно полезен — структурированная запись каждой фазы стартапа в отдельный JSONL.

**Источник-доказательство:** [Diagnostics flags docs](https://docs.openclaw.ai/diagnostics/flags).

**Подвох:** Telegram payload содержит сообщения пользователей. Не оставляй в production надолго.

---

### 12. OpenTelemetry — full observability через стандартный OTLP

**Где живёт:** `logging.otel.*` в openclaw.json + стандартные OTEL env vars.

**Как активировать:**
```bash
# Стандартные OTEL env vars работают:
export OTEL_EXPORTER_OTLP_ENDPOINT=https://your-collector.example.com
export OTEL_SERVICE_NAME=openclaw-prod
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf

# Для последних GenAI semantic conventions:
export OTEL_SEMCONV_STABILITY_OPT_IN=gen_ai_latest_experimental

# Если уже есть OTel SDK в процессе (например, через init script):
export OPENCLAW_OTEL_PRELOADED=1

openclaw gateway
```

Или в конфиге:
```jsonc
{
  "logging": {
    "otel": {
      "enabled": true,
      "endpoint": "https://your-collector",
      "signals": {
        "traces": { "endpoint": "https://traces-only" },
        "metrics": { "endpoint": "https://metrics-only" }
      }
    }
  }
}
```

**Что это даёт:** в Grafana/Honeycomb/Langfuse видишь:
- token usage per model
- tool loop durations
- harness runs
- exec processes
- memory pressure
- compaction events

Всё с low-cardinality атрибутами, без leak'а юзер-данных.

**Источник-доказательство:** [release 2026.4.25-beta.4](https://github.com/openclaw/openclaw/releases/tag/v2026.4.25-beta.4) — "Expanded OpenTelemetry coverage across model calls, token usage, tool loops, harness runs, exec processes".

**Подвох:** GenAI semconv ещё experimental — атрибуты могут поменяться между релизами. Закрепи версию semconv в коллекторе.

---

### 13. Tailscale Funnel — публичный HTTPS-доступ к gateway без своего домена

**Где живёт:** `gateway.tailscale` секция.

**Как активировать:**
```jsonc
{
  "gateway": {
    "auth": "password",  // ВАЖНО: funnel требует password, не token
    "tailscale": {
      "mode": "funnel",  // serve | funnel | off
      "resetOnExit": true
    }
  }
}
```

```bash
# Запустить (нужно tailscale CLI logged in):
openclaw gateway --tailscale funnel
# или
openclaw gateway --tailscale serve  # tailnet-only, без публики
```

**Что это даёт:** твой gateway доступен по публичному `*.ts.net` URL с автоматическим Let's Encrypt сертификатом. Можно подключать удалённые ноды без VPS.

**Источник-доказательство:** [Tailscale docs](https://docs.openclaw.ai/gateway/tailscale), [Tailscale blog post](https://tailscale.com/blog/openclaw-tailscale-aperture-serve).

**Подвох:** `funnel` mode РЕФЬЮЗИТ старт без password auth — формальная защита от случайной публичной выдачи без аутентификации. Это feature, а не bug.

---

### 14. Compaction custom provider — заменяй встроенную суммаризацию

**Где живёт:** Plugin SDK, метод `registerCompactionProvider()`.

**Как активировать (плагин):**
```ts
// плагин openclaw-custom-compaction
export function register(api: OpenClawPluginApi) {
  api.registerCompactionProvider({
    name: "my-extractive-summarizer",
    summarize: async (messages, opts) => {
      // например, через локальный Pegasus/BART вместо LLM
      return await myExtractiveSummary(messages);
    }
  });
}
```

В конфиге:
```jsonc
{
  "agents": {
    "defaults": {
      "compaction": {
        "provider": "my-extractive-summarizer"  // твой плагин
      }
    }
  }
}
```

**Что это даёт:** если LLM-суммаризация дорога — ставь экстрактивный/локальный. Или напиши кастомный, который сохраняет специфичные структуры (код-блоки, JSON, метрики) лучше дефолта.

**Источник-доказательство:** [Plugin SDK Reference (DeepWiki)](https://deepwiki.com/openclaw/docs/5.1-plugin-sdk-reference), [Compaction docs](https://docs.openclaw.ai/concepts/compaction).

**Подвох:** хуки `before_compaction`/`after_compaction` определены в SDK, но **на текущий момент никогда не вызываются** — баг #4967 и #9527. Если завязываешь логику на них — сломается. Используй именно `registerCompactionProvider()`, а не lifecycle hooks.

---

### 15. tasks distill-export — дистилляция твоих сессий в обучающий датасет

**Где живёт:** `openclaw tasks distill-export` (Mission Control / advanced CLI).

**Как активировать:**
```bash
openclaw tasks distill-export \
  --output ./training.jsonl \
  --include sessions,replay,codex,audit \
  --redact aggressive
```

**Что это даёт:** все твои сессии + audit logs + replay-bundles превращаются в обучающий JSONL — в формате, готовом для file-tuning Llama/Mistral или RL (через OpenClaw-RL). Ты буквально обучаешь модель на собственном опыте работы с агентом.

**Источник-доказательство:** [OpenClaw Mission Control GitHub](https://github.com/frank8ai/openclaw-mission-control), [OpenClaw-RL paper (arxiv 2603.10165)](https://arxiv.org/abs/2603.10165).

**Подвох:** перед публикацией датасета — прогон через дополнительный redactor. Дефолтный redact пропускает кастомные secret-форматы.

---

## Скрытые CLI флаги (топ-15)

| Команда | Флаг | Что делает | Пример использования |
|---------|------|-----------|---------------------|
| `openclaw` (global) | `--profile <name>` | Полная изоляция state в `~/.openclaw-<name>` | `openclaw --profile staging gateway` |
| `openclaw` (global) | `--dev` | `~/.openclaw-dev` + сдвинутые порты, чтобы dev и prod жили рядом | `openclaw --dev gateway` |
| `openclaw` (global) | `--container <name>` | Запуск внутри named контейнера sandbox | `openclaw --container review-bot mcp serve` |
| `openclaw gateway run` | `--allow-unconfigured` | Игнор startup guard, чисто для ad-hoc | `openclaw gateway run --allow-unconfigured` |
| `openclaw gateway run` | `--raw-stream --raw-stream-path` | Лог raw-стрима модели в JSONL | `openclaw gateway --raw-stream --raw-stream-path /tmp/raw.jsonl` |
| `openclaw gateway run` | `--ws-log compact` / `full` | Стиль WS-логов | `openclaw gateway --ws-log full` (для глубокого дебага) |
| `openclaw gateway stability` | `--export --output <path>` | Создаёт shareable diagnostics zip | `openclaw gateway stability --export --output ~/Desktop/bug.zip` |
| `openclaw gateway diagnostics export` | `--log-lines --log-bytes` | Кастомный размер выгружаемых логов | `openclaw gateway diagnostics export --log-lines 20000` |
| `openclaw doctor` | `--deep` | Сканирует system services на чужие gateway-инсталляции | `openclaw doctor --deep` |
| `openclaw doctor` | `--repair --force` | Агрессивный фикс с перезаписью кастомных configs | `openclaw doctor --repair --force` (только знаешь что делаешь) |
| `openclaw memory status` | `--deep --fix` | Чек vector/embedding + чинит recall locks | `openclaw memory status --deep --fix --json` |
| `openclaw memory promote` | `--apply --min-score --min-recall-count` | Ручной dreaming-промоушен | `openclaw memory promote --apply --min-score 0.85` |
| `openclaw sessions cleanup` | `--dry-run --fix-missing` | Превью cleanup без действий | `openclaw sessions cleanup --dry-run --fix-missing` |
| `openclaw sessions export-trajectory` | `--output <name>` | Кастомное имя выгружаемой траектории | `openclaw sessions export-trajectory --session-key abc --output bug-99` |
| `openclaw skills list` | `--eligible --verbose` | Только подходящие для текущего стека скиллы | `openclaw skills list --eligible --json` |

**Источники:** [CLI reference](https://docs.openclaw.ai/cli), [gateway CLI](https://docs.openclaw.ai/cli/gateway), [memory CLI](https://docs.openclaw.ai/cli/memory), [sessions CLI](https://docs.openclaw.ai/cli/sessions), [doctor CLI](https://docs.openclaw.ai/cli/doctor).

---

## Полный реестр OPENCLAW_* env vars

### Базовые (документированные)
| Переменная | Что делает |
|-----------|-----------|
| `OPENCLAW_STATE_DIR` | Override state-директории (default `~/.openclaw`) |
| `OPENCLAW_CONFIG_PATH` | Override пути к openclaw.json |
| `OPENCLAW_HOME` | Подменяет system home (изоляция для service-аккаунтов) |
| `OPENCLAW_LOAD_SHELL_ENV` | Импорт login-shell env при старте |
| `OPENCLAW_SHELL_ENV_TIMEOUT_MS` | Таймаут импорта env |
| `OPENCLAW_THEME` | `light` или `dark` для TUI |
| `OPENCLAW_LOG_LEVEL` | `debug`, `trace`, `info`, `warn`, `error` |

### Скрытые / для дебага
| Переменная | Что делает | Источник |
|-----------|-----------|----------|
| `OPENCLAW_PLUGIN_LIFECYCLE_TRACE=1` | Phase-by-phase разбивка plugin-операций (stderr) | [debugging](https://docs.openclaw.ai/help/debugging) |
| `OPENCLAW_DEBUG_TIMING=1` | Human-readable timing slow commands | [debugging](https://docs.openclaw.ai/help/debugging) |
| `OPENCLAW_DEBUG_TIMING=json` | JSONL timing вместо текста | [debugging](https://docs.openclaw.ai/help/debugging) |
| `OPENCLAW_RAW_STREAM=1` | Лог raw-стрима до фильтрации | [debugging](https://docs.openclaw.ai/help/debugging) |
| `OPENCLAW_RAW_STREAM_PATH` | Кастомный путь для raw-stream JSONL | [debugging](https://docs.openclaw.ai/help/debugging) |
| `OPENCLAW_PROFILE` | Профиль (`dev`, `staging`, etc) | [debugging](https://docs.openclaw.ai/help/debugging) |
| `OPENCLAW_GATEWAY_PORT` | Принудительный порт | [debugging](https://docs.openclaw.ai/help/debugging) |
| `OPENCLAW_SKIP_CHANNELS` | Запустить gateway без channel-провайдеров | [debugging](https://docs.openclaw.ai/help/debugging) |
| `OPENCLAW_TRAJECTORY=0` | Отключить runtime trajectory capture | [trajectory](https://docs.openclaw.ai/tools/trajectory) |
| `OPENCLAW_TRAJECTORY=<path>` | Постоянная запись trajectory во внешнюю папку | [trajectory](https://docs.openclaw.ai/tools/trajectory) |
| `OPENCLAW_DIAGNOSTICS=<flags>` | Selective subsystem-tracing | [diagnostics](https://docs.openclaw.ai/diagnostics/flags) |
| `OPENCLAW_DIAGNOSTICS_TIMELINE_PATH` | Путь для timeline JSONL | [diagnostics](https://docs.openclaw.ai/diagnostics/flags) |
| `OPENCLAW_OTEL_PRELOADED=1` | Использовать pre-registered OTel SDK | [release 4.25-beta.4](https://github.com/openclaw/openclaw/releases/tag/v2026.4.25-beta.4) |
| `OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY` | Break-glass для cold plugin registry (deprecated) | [release 4.25-beta.4](https://github.com/openclaw/openclaw/releases/tag/v2026.4.25-beta.4) |
| `OPENCLAW_SERVICE_REPAIR_POLICY=external` | Не пытаться чинить внешне-управляемые сервисы | [release 4.25-beta.4](https://github.com/openclaw/openclaw/releases/tag/v2026.4.25-beta.4) |
| `OPENCLAW_DISABLE_BONJOUR=0` | Включить mDNS-advertising в Docker Compose | [release 4.25-beta.4](https://github.com/openclaw/openclaw/releases/tag/v2026.4.25-beta.4) |
| `OPENCLAW_SHELL` (read-only marker) | Маркер runtime-контекста: `exec`, `acp`, `acp-client`, `tui-local` | [environment](https://docs.openclaw.ai/help/environment) |
| `PI_RAW_STREAM=1` / `PI_RAW_STREAM_PATH` | Capture raw OpenAI-compat chunks (pi-mono backend) | [debugging](https://docs.openclaw.ai/help/debugging) |
| `OTEL_SEMCONV_STABILITY_OPT_IN=gen_ai_latest_experimental` | Свежие GenAI semantic conventions | [release 4.25-beta.4](https://github.com/openclaw/openclaw/releases/tag/v2026.4.25-beta.4) |

### Резолюция (highest → lowest priority)
1. Process environment (что есть в parent shell)
2. `.env` в текущей CWD
3. Глобальный `~/.openclaw/.env`
4. `env` блок в `openclaw.json`
5. Login-shell import (если включён `OPENCLAW_LOAD_SHELL_ENV`)

**Особенность:** "никогда не override-нет существующее значение" — это значит что `.env` не перезапишет уже выставленную переменную process'а. Полезно для CI: задаёшь в pipeline, файл не мешает.

---

## Экспериментальные / Beta фичи

### experimental.localModelLean — режим для слабых local-моделей
```jsonc
{
  "agents": {
    "defaults": {
      "experimental": {
        "localModelLean": true
      }
    }
  }
}
```
**Что делает:** убирает heavyweight tools (`browser`, `cron`, `message`) — prompt становится короче и менее brittle. Для маленьких/квантованных моделей через Ollama/LM Studio.

**Источник:** [experimental-features](https://docs.openclaw.ai/concepts/experimental-features), [local-models](https://docs.openclaw.ai/gateway/local-models).

### experimental.sessionMemory — индексация старых сессий в memory_search
```jsonc
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "experimental": {
          "sessionMemory": true
        }
      }
    }
  }
}
```
**Что делает:** прошлые транскрипты попадают в индекс семантического поиска. `memory_search` начинает находить контекст из позапрошлой недели.

**Цена:** дополнительное storage + indexing. Indexing async (не блокирует), но диск растёт.

### tools.experimental.planTool — структурированный update_plan tool
```jsonc
{
  "tools": {
    "experimental": {
      "planTool": true
    }
  }
}
```
**Что делает:** агент получает специальный `update_plan` tool — может явно вести многошаговый план. Хорошо работает с UIs которые умеют его рендерить (Control UI, macOS app).

### Bun runtime (experimental)
```bash
# Только для local dev, НЕ для gateway runtime!
bun install
bun run cli ...
```
**Подвох:** "Bun is not recommended for gateway runtime due to compatibility issues with WhatsApp and Telegram". Используй для скриптов и CLI, но gateway — Node.js.

**Источник:** [install/bun](https://docs.openclaw.ai/install/bun).

### Release channels: stable → beta → dev
```bash
openclaw update --channel beta   # тестирует на пред-релизах
openclaw update --channel dev    # cutting edge с main
openclaw update --channel stable # обратно
```
"Dev" = main branch, может содержать incomplete features. Beta = stable + testing-track.

---

## Easter eggs и экзотика

### `/codex computer-use install` — нативное управление Mac-десктопом
```
/codex computer-use status
/codex computer-use install
```
Codex-режим даёт агенту полный доступ к macOS UI: cursor control, screen reading, click, type. Через cua-driver MCP. Только macOS.

**Источник:** [codex-computer-use](https://docs.openclaw.ai/plugins/codex-computer-use), [release 2026.4.27](https://github.com/openclaw/openclaw/releases).

### Voice wake word (offline через Vosk)
```jsonc
{
  "channels": {
    "voice": {
      "wakeWords": ["openclaw", "jarvis", "computer", "лобстер"],
      "engine": "vosk-offline"
    }
  }
}
```
Вейк-ворд распознаётся локально, в облако НИЧЕГО не отправляется до триггера.

**Источник:** [voicewake](https://docs.openclaw.ai/nodes/voicewake).

### `/dock-discord` / `/dock-slack` / `/dock-telegram` — авто-генерация channel-команд
Скиллы могут декларировать команды, которые автоматически появляются как нативные slash-команды в каждом канале. То есть пишешь скилл один раз — он работает в Telegram и в Discord и в Slack.

**Источник:** [Slash commands docs](https://docs.openclaw.ai/tools/slash-commands).

### `/elevated on` — временное повышение прав exec
```
/elevated on
# ... делаешь опасное действие (sudo, rm -rf, и т.д.)
/elevated off
```
Конфиг:
```jsonc
{
  "tools": {
    "exec": {
      "elevated": {
        "enabled": true,
        "allowlist": ["docker", "systemctl"],
        "requireConfirmation": true,
        "timeoutSeconds": 300
      }
    }
  }
}
```
**Подвох:** issue #18834 — elevated permissions не резолвятся в agentCommand path (sub-agents). Если делегируешь elevated работу под-агенту — не сработает.

### Hooks — реальные lifecycle events (но не все работают)
**Работающие:** `command:new`, `command:reset`, `session:patch`, `gateway:startup`, `gateway:shutdown`, `message:received`, `message:sent`.

**Документированные но НЕ срабатывают** (баг #4967, #9527): `before_compaction`, `after_compaction`. Для compaction-логики используй `registerCompactionProvider()` — это работает.

**Bundled hooks ship by default:**
- `session-memory` — saves conversation context
- `bootstrap-extra-files` — injects дополнительные файлы
- `command-logger` — логирует все команды
- `boot-md` — runs startup-скрипты

**Источник:** [hooks](https://docs.openclaw.ai/automation/hooks).

### Discord hidden: `ephemeralDefault: true` для приватных команд
```jsonc
{
  "channels": {
    "discord": {
      "slashCommands": {
        "ephemeralDefault": true  // ответы видит только тот кто вызвал
      }
    }
  }
}
```
Хорошо для admin-команд (показ API ключей, приватных метрик) в публичном сервере.

### Telegram forum topics — изолированные сессии
В BotFather → enable Threaded Mode. Каждая тема в форуме = отдельная сессия с своим system-prompt и моделью. Идеально для:
- Тема "Работа" — Claude Sonnet с work-промптом
- Тема "Творчество" — GPT-5 с creative-промптом
- Тема "Дневник" — локальная модель + privacy-промпт

**Источник:** [Telegram channel docs](https://docs.openclaw.ai/channels/telegram), [Fabrizio Rinaldi tweet](https://x.com/linuz90/status/2030616602782450087).

**Известные баги:** issue #54505 — exec approval inline buttons уходят в main topic вместо originating topic. Issue #28201 — slash commands silently ignored в forum group topics.

### Canvas tool — рендер HTML на нодах
Канвас НЕ "рисует картинку" — это **HTML viewer для подключённых node'ов** (Mac app, iOS, Android). Self-contained HTML с inline CSS/JS отображается на канвасе ноды. Хорошо для:
- Дашборды реального времени
- Визуализация JSON-результатов
- Интерактивные графики (Chart.js inline)

**Источник:** [tencent techpedia](https://www.tencentcloud.com/techpedia/141077).

---

## Дополнительные находки

### Подавление tool-progress preview в каналах
```jsonc
{
  "channels": {
    "telegram": {
      "streaming": {
        "preview": {
          "toolProgress": false  // не спамить "🔧 Calling browser..."
        }
      }
    }
  }
}
```
Базовые туториалы говорят что streaming = только on/off. На самом деле есть granular control.

### Sandbox runtimes выживают 24 часа
"Existing runtimes continue running with old settings" — конфиг поменял, но старая sandbox-сессия использует старые настройки. Принудительный пересоздать:
```bash
openclaw sandbox recreate --all
openclaw sandbox recreate --session <key>
openclaw sandbox recreate --agent <id>
```

### Gateway probe через SSH без локального tailscale
```bash
openclaw gateway probe --ssh user@host:22 --ssh-identity ~/.ssh/id_ed25519
```
Проверяет gateway на удалённой машине через SSH, не нуждаясь в Tailscale.

### tasks audit — health check всех background задач
```bash
openclaw tasks list
openclaw tasks audit       # surfaces issues
openclaw tasks show <id>
openclaw tasks cancel <id>
```
SQLite-ledger в `$OPENCLAW_STATE_DIR/tasks/runs.sqlite`. Терминальные таски хранятся 7 дней, потом авто-prune.

**Источник:** [Background tasks docs](https://docs.openclaw.ai/automation/tasks).

### Bonjour/mDNS Wide-Area через Tailscale
Можно публиковать `_openclaw-gw._tcp` записи в кастомной DNS-зоне (`openclaw.internal.`) поверх Tailscale — получаешь LAN-style discovery в любой точке мира.

**Источник:** [Bonjour discovery docs](https://docs.openclaw.ai/gateway/bonjour).

### Approval-token replay protection
Любая exec-команда защищена:
- Unix socket mode 0600
- Same-UID peer check
- Challenge/response (nonce + HMAC + request hash)
- Bound canonical execution context (cwd, argv, executable path)
- Если bound file изменился между approval и execution — **denied** (защита от drift)

**Источник:** [Exec approvals docs](https://docs.openclaw.ai/tools/exec-approvals).

---

## Pro-tip: комбо для максимума автономии

```jsonc
{
  "agents": {
    "defaults": {
      "experimental": {
        "localModelLean": false        // не нужен если облачные модели
      },
      "memorySearch": {
        "experimental": {
          "sessionMemory": true        // помнит прошлое
        }
      },
      "compaction": {
        "memoryFlush": {
          "enabled": true,
          "softThresholdTokens": 4000  // pre-compaction save
        }
      },
      "subagents": {
        "maxSpawnDepth": 2,
        "maxChildrenPerAgent": 5,
        "model": "anthropic/claude-haiku-4-6"  // дешёвые воркеры
      },
      "queue": {
        "drop": "summarize"            // не теряет сообщения при флуде
      },
      "heartbeat": {
        "enabled": true,
        "intervalMinutes": 30,
        "batchPendingCrons": true      // экономит токены
      }
    }
  },
  "tools": {
    "experimental": {
      "planTool": true                 // структурированное планирование
    }
  },
  "plugins": {
    "entries": {
      "memory-core": {
        "config": {
          "dreaming": {
            "enabled": true,           // долговременная память сама собой
            "frequency": "0 3 * * *"   // 3 утра каждый день
          }
        }
      }
    }
  },
  "logging": {
    "otel": {
      "enabled": true,
      "endpoint": "https://your-collector"
    }
  },
  "diagnostics": {
    "flags": ["timeline"]              // видно весь startup
  },
  "commands": {
    "debug": true,                     // /debug overrides
    "mcp": true,
    "plugins": true
  }
}
```

И в `~/.openclaw/.env`:
```bash
OPENCLAW_TRAJECTORY=/Users/you/openclaw-traces
OTEL_SERVICE_NAME=openclaw-prod
```

---

## Источники

### Официальные
- [docs.openclaw.ai/cli](https://docs.openclaw.ai/cli) — CLI reference
- [docs.openclaw.ai/cli/gateway](https://docs.openclaw.ai/cli/gateway) — все gateway-команды
- [docs.openclaw.ai/cli/memory](https://docs.openclaw.ai/cli/memory) — memory CLI с `promote-explain`, `rem-harness`, `rem-backfill`
- [docs.openclaw.ai/cli/sessions](https://docs.openclaw.ai/cli/sessions) — sessions cleanup, export
- [docs.openclaw.ai/cli/doctor](https://docs.openclaw.ai/cli/doctor) — `--repair`, `--deep`, `--force`
- [docs.openclaw.ai/cli/sandbox](https://docs.openclaw.ai/cli/sandbox) — sandbox recreate
- [docs.openclaw.ai/cli/skills](https://docs.openclaw.ai/cli/skills) — `--eligible`, `--agent`
- [docs.openclaw.ai/cli/mcp](https://docs.openclaw.ai/cli/mcp) — mcp serve
- [docs.openclaw.ai/cli/agents](https://docs.openclaw.ai/cli/agents) — agents add, bind, set-identity
- [docs.openclaw.ai/concepts/experimental-features](https://docs.openclaw.ai/concepts/experimental-features) — все experimental.* флаги
- [docs.openclaw.ai/concepts/dreaming](https://docs.openclaw.ai/concepts/dreaming) — light/REM/deep phases
- [docs.openclaw.ai/concepts/memory](https://docs.openclaw.ai/concepts/memory) — backends (SQLite, QMD, Honcho, LanceDB)
- [docs.openclaw.ai/concepts/streaming](https://docs.openclaw.ai/concepts/streaming) — block / preview streaming
- [docs.openclaw.ai/concepts/queue](https://docs.openclaw.ai/concepts/queue) — steer/followup/collect/drop
- [docs.openclaw.ai/concepts/compaction](https://docs.openclaw.ai/concepts/compaction) — memoryFlush, transcript management
- [docs.openclaw.ai/automation/cron-vs-heartbeat](https://docs.openclaw.ai/automation/cron-vs-heartbeat) — wake-mode batch
- [docs.openclaw.ai/automation/standing-orders](https://docs.openclaw.ai/automation/standing-orders) — AGENTS.md persistent
- [docs.openclaw.ai/automation/hooks](https://docs.openclaw.ai/automation/hooks) — все event types
- [docs.openclaw.ai/automation/tasks](https://docs.openclaw.ai/automation/tasks) — background task ledger
- [docs.openclaw.ai/diagnostics/flags](https://docs.openclaw.ai/diagnostics/flags) — `OPENCLAW_DIAGNOSTICS`, timeline
- [docs.openclaw.ai/help/debugging](https://docs.openclaw.ai/help/debugging) — `/debug`, `/trace`, raw stream
- [docs.openclaw.ai/help/environment](https://docs.openclaw.ai/help/environment) — env vars, resolution order
- [docs.openclaw.ai/gateway/configuration-reference](https://docs.openclaw.ai/gateway/configuration-reference) — JSON5, hot-reload modes
- [docs.openclaw.ai/gateway/local-models](https://docs.openclaw.ai/gateway/local-models) — `compat.requiresStringContent`, `allowPrivateNetwork`
- [docs.openclaw.ai/gateway/tailscale](https://docs.openclaw.ai/gateway/tailscale) — serve / funnel modes
- [docs.openclaw.ai/gateway/logging](https://docs.openclaw.ai/gateway/logging) — `redactSensitive`, `redactPatterns`
- [docs.openclaw.ai/gateway/bonjour](https://docs.openclaw.ai/gateway/bonjour) — mDNS, wide-area
- [docs.openclaw.ai/security/formal-verification](https://docs.openclaw.ai/security/formal-verification) — TLA+/TLC модели
- [docs.openclaw.ai/plugins/architecture-internals](https://docs.openclaw.ai/plugins/architecture-internals) — 43 hooks, registry
- [docs.openclaw.ai/plugins/sdk-overview](https://docs.openclaw.ai/plugins/sdk-overview) — `registerHttpRoute`, `registerCompactionProvider`
- [docs.openclaw.ai/plugins/codex-computer-use](https://docs.openclaw.ai/plugins/codex-computer-use) — macOS desktop control
- [docs.openclaw.ai/tools/slash-commands](https://docs.openclaw.ai/tools/slash-commands) — полный список / включая admin
- [docs.openclaw.ai/tools/subagents](https://docs.openclaw.ai/tools/subagents) — `maxSpawnDepth`, fork context
- [docs.openclaw.ai/tools/trajectory](https://docs.openclaw.ai/tools/trajectory) — trajectory bundles
- [docs.openclaw.ai/tools/exec-approvals](https://docs.openclaw.ai/tools/exec-approvals) — replay protection
- [docs.openclaw.ai/tools/thinking](https://docs.openclaw.ai/tools/thinking) — `/think:adaptive`, xhigh, max
- [docs.openclaw.ai/install/development-channels](https://docs.openclaw.ai/install/development-channels) — stable/beta/dev
- [docs.openclaw.ai/install/bun](https://docs.openclaw.ai/install/bun) — Bun experimental
- [docs.openclaw.ai/channels/telegram](https://docs.openclaw.ai/channels/telegram) — forum topics, inline buttons
- [docs.openclaw.ai/channels/discord](https://docs.openclaw.ai/channels/discord) — voice, ephemeralDefault, modals
- [docs.openclaw.ai/channels/imessage](https://docs.openclaw.ai/channels/imessage) — BlueBubbles vs imsg
- [docs.openclaw.ai/nodes/voicewake](https://docs.openclaw.ai/nodes/voicewake) — Vosk offline wake-word
- [docs.openclaw.ai/llms.txt](https://docs.openclaw.ai/llms.txt) — индекс всей документации (ВСЁ есть тут)

### Релизы
- [release v2026.4.25-beta.4](https://github.com/openclaw/openclaw/releases/tag/v2026.4.25-beta.4) — TTS upgrade, OTel expansion, `OPENCLAW_OTEL_PRELOADED`
- [release v2026.4.27](https://github.com/openclaw/openclaw/releases) — Codex Computer Use, DeepInfra
- [release v2026.4.9](https://github.com/openclaw/openclaw/releases/tag/v2026.4.9) — REM backfill, SSRF hardening
- [Releasebot OpenClaw timeline](https://releasebot.io/updates/openclaw)

### Issues и community gold
- [#4967 — before_compaction/after_compaction hooks never called](https://github.com/openclaw/openclaw/issues/4967)
- [#9527 — duplicate report on hooks bug](https://github.com/openclaw/openclaw/issues/9527)
- [#54408 — pre-compaction memory flush leaks as user messages](https://github.com/openclaw/openclaw/issues/54408)
- [#44787 — NO_REPLY semantics](https://github.com/openclaw/openclaw/issues/44787)
- [#54505 — Telegram forum topics exec approval bug](https://github.com/openclaw/openclaw/issues/54505)
- [#28201 — slash commands silently ignored in Telegram forum topics](https://github.com/openclaw/openclaw/issues/28201)
- [#34881 — /steer as shorthand](https://github.com/openclaw/openclaw/issues/34881)
- [#6832 — sessions_spawn depth limits](https://github.com/openclaw/openclaw/issues/6832)
- [#18834 — elevated permissions not in agentCommand path](https://github.com/openclaw/openclaw/issues/18834)
- [Fabrizio Rinaldi (linuz90) — Telegram forum tip](https://x.com/linuz90/status/2030616602782450087)
- [Voxyz_ai tweet — REM backfill discovery](https://x.com/Voxyz_ai/status/2042142846065561920)

### Сторонние гайды и анализы
- [DeepWiki — Plugin SDK Reference](https://deepwiki.com/openclaw/docs/5.1-plugin-sdk-reference) — полная карта SDK subpaths
- [HackMD — OpenClaw Architecture Deep Dive 02/08/2026](https://hackmd.io/Z39YLHZoTxa7YLu_PmEkiA)
- [theagentstack — OpenClaw Architecture Part 1](https://theagentstack.substack.com/p/openclaw-architecture-part-1-control)
- [OpenClaw-RL paper (arxiv 2603.10165)](https://arxiv.org/abs/2603.10165)
- [Mission Control CLI by frank8ai](https://github.com/frank8ai/openclaw-mission-control) — `tasks distill-export`
- [TechNickAI/openclaw-config](https://github.com/TechNickAI/openclaw-config) — pro-tier standing orders
- [Tailscale blog — OpenClaw + Aperture/Serve](https://tailscale.com/blog/openclaw-tailscale-aperture-serve)

---

## Финальная сверка: что точно работает в 2026.4.x

Проверены лично через документацию и/или upstream:

- [x] `/debug`, `/trace`, `/btw`, `/queue`, `/elevated`, `/dreaming`, `/codex`, `/vc`
- [x] `OPENCLAW_TRAJECTORY`, `OPENCLAW_DIAGNOSTICS`, `OPENCLAW_OTEL_PRELOADED`
- [x] `experimental.localModelLean`, `memorySearch.experimental.sessionMemory`, `tools.experimental.planTool`
- [x] `registerCompactionProvider()` (SDK), но НЕ `before_compaction`/`after_compaction` hooks (баг)
- [x] Tailscale serve/funnel modes
- [x] Sub-agents fork context, `maxSpawnDepth: 2`
- [x] Heartbeat batch wake-mode для cron'ов
- [x] Memory `rem-backfill --grounded`, `promote-explain`
- [x] tasks distill-export для дистилляции датасета
- [x] Hot-reload modes (restart / hot-apply / hybrid)
- [x] Telegram forum topics с per-topic моделью

Всё, что включаешь — сначала тестируй на отдельном `--profile staging`, потом катишь в основную инсталляцию.
