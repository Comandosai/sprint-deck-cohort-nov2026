# 💰 Эксклюзивные техники: Cost & Performance для OpenClaw

> Pro-tips от опытных пользователей OpenClaw — то, что НЕ пишут в стандартных туториалах.
> Это не «включите Haiku вместо Opus» — это то, что находишь на 30-й странице GitHub Discussions, в issue-репортах и постах инженеров, которые уже спалили $500+.
>
> **Дата сборки:** апрель 2026
> **Применимо к:** OpenClaw stable (`gateway`-конфиг, `agents.defaults`, `cron`, `heartbeat`, `auth.cooldowns`)
> **Дополняет (не дублирует):** Блок 03 (LLM-провайдеры), Блок 12 (Проактивность), Блок 16 (Multi-agent), Блок 20 (Режим бога)

---

## 📊 Калькулятор реальных трат — что реально жрёт деньги

По данным OpenClaw community (Discussion #11042, Issue #43767, Habr-обсуждения апрель 2026), **60-80% бюджета** среднего агента уходит **не на полезную работу**, а на:

| Источник | Доля бюджета | Реальный кейс |
|---|---|---|
| Context accumulation (растущая история без compact) | **40-50%** | Один пользователь — $3,600/мес на одиночном агенте |
| Heartbeat без `lightContext` | **20-30%** | $50 за день с интервалом 5 мин и full-context |
| Model misrouting (Opus вместо Haiku на trivial tasks) | **15-20%** | Opus $5/$25 vs Haiku $1/$5 за миллион токенов |
| Cache miss из-за timestamps в system prompt | **10-15%** | -90% economy vs. -0%, потому что 1 токен сломал prefix |
| Tool result spam (длинные ответы tools без trimming) | **5-10%** | 12-15K токенов на «грязный» bash output |

Источник: [Heartbeats in OpenClaw — Cheap Checks First](https://dev.to/damogallagher/heartbeats-in-openclaw-cheap-checks-first-models-only-when-you-need-them-4bfi), [Discussion #11042](https://github.com/openclaw/openclaw/discussions/11042), [LaoZhang AI Cost Optimization](https://blog.laozhang.ai/en/posts/openclaw-save-money-practical-guide).

**Базовая модель расчёта:**

```
Месячный бюджет (Sonnet primary) =
  (heartbeat_runs × heartbeat_tokens × $3/M_input)
  + (chat_turns × (system_prompt + history) × $3/M_input)
  + (chat_turns × output × $15/M_output)
  + (tool_calls × tool_result_tokens × $3/M_input)
  − cache_hit_savings (до −90%)
  − batch_savings (до −50%)

Реальный минимум 2026 при правильной настройке: $20-40/мес для personal-агента.
Реальный максимум при misconfiguration: $600-3600/мес.
```

---

## 🔥 Топ-22 эксклюзивных техники экономии (с цифрами)

### 1. `cacheRetention: "long"` + heartbeat 55 мин — экономия до 90% на input
**Что:** Anthropic «extended cache» с TTL 1 час доступен через `cache_control.ttl: "1h"`. OpenClaw поддерживает это через параметр `cacheRetention: "long"`.
**Как:**
```yaml
# openclaw.json (yaml-вариант)
agents:
  defaults:
    params:
      cacheRetention: "long"   # 1-hour TTL вместо 5 минут
heartbeat:
  intervalMinutes: 55          # пере-греваем кэш ДО его истечения
  lightContext: true
```
**Экономия:** cache-read стоит **0.1×** базовой цены input (Anthropic public pricing). Если у тебя стабильный 50-90K токенный prefix — это **−85-90%** input-расходов.
**Подвох:** cache-write стоит **2× базовой цены** при 1h TTL (vs 1.25× для 5-min). Если запросы случайные и реже 1 раза в час — long дороже short. Heartbeat-разогрев каждые 55 мин окупается, только если в окне идут реальные запросы.
**Источник:** [Anthropic Prompt Caching Docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching), [OpenClaw Prompt Caching reference](https://docs.openclaw.ai/reference/prompt-caching), [Claude cache TTL silently changed Mar 2026](https://github.com/anthropics/claude-code/issues/46829).

---

### 2. Все 4 cache_control breakpoints на стратегических границах — экономия +15-25% поверх обычного caching
**Что:** Anthropic даёт **до 4 breakpoints** в одном запросе. Большинство пользователей ставит один — и теряют деньги, когда меняется любой блок выше последнего.
**Как:** разместить breakpoints на 4 уровнях стабильности:
1. **Tools** (меняются раз в неделю) — cache_control здесь
2. **System prompt static-часть** (меняется при релизе) — cache_control
3. **Skills/memories baseline** (меняется раз в день) — cache_control
4. **Conversation history до текущего turn** (меняется каждый turn) — cache_control

```python
# Псевдокод для openclaw plugin или Anthropic SDK прямого вызова
messages = [
    {"role": "system", "content": [
        {"type": "text", "text": TOOLS_DESCRIPTION,
         "cache_control": {"type": "ephemeral", "ttl": "1h"}},  # bp1
        {"type": "text", "text": SYSTEM_STATIC,
         "cache_control": {"type": "ephemeral", "ttl": "1h"}},  # bp2
        {"type": "text", "text": SKILLS_AND_MEMORIES,
         "cache_control": {"type": "ephemeral"}},               # bp3
    ]},
    *history_with_cache_control_on_last_old_msg,                # bp4
    {"role": "user", "content": new_user_message}               # без cache_control
]
```
**Экономия:** при 4 breakpoints cache hit-rate на длинных диалогах поднимается с ~75% до ~96% (данные OpenAI live-метрик по prefix-stable: 0.966 hit rate, [OpenClaw docs](https://docs.openclaw.ai/reference/prompt-caching)). Это **+15-25%** к экономии поверх «один breakpoint в конце system».
**Подвох:** **20-block lookback window** — breakpoint видит только 20 content-блоков назад. В длинных tool-loops верхние breakpoints выпадают из окна. Решение: явно реставрировать их при каждой компакции.
**Источник:** [Spring AI Prompt Caching — 4 breakpoint patterns](https://spring.io/blog/2025/10/27/spring-ai-anthropic-prompt-caching-blog/), [Mastering Claude Prompt Caching 2025](https://sparkco.ai/blog/mastering-claude-prompt-caching-techniques-for-2025).

---

### 3. Anthropic Message Batches API — −50% на ВСЕ async-задачи
**Что:** для любых задач, где результат можно подождать до 24ч (правда, в практике 1-6ч), Anthropic даёт ровный **−50% и на input, и на output**. Чистая магия.
**Как (применимо к OpenClaw):**
- ночные `cron`-задачи (саммаризация почты, дайджесты, ревью PR за день)
- batch-классификация лидов / уведомлений
- генерация еженедельных отчётов из памяти

```bash
# отдельный воркер, который раз в час собирает batch-eligible jobs из очереди:
curl https://api.anthropic.com/v1/messages/batches \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"requests":[{"custom_id":"job_1","params":{...}}, ...]}'
# до 10000 запросов в одном batch
```

В `openclaw.json` это делается через выделенного `batchAgent` с custom-провайдером:
```json5
{
  "agents": {
    "list": [
      {"id": "batch-digest", "model": {"primary": "claude-sonnet-4-6@batch"}}
    ]
  }
}
```
**Экономия:** **−50%** на всём. Плюс отдельный rate-limit pool — большие задачи не съедают real-time лимиты.
**Подвох:** **строго асинхронно**. Не годится для интерактивного чата. Также — если batch упал (24ч timeout), ты теряешь ничего, но и результата нет. Для OpenClaw: вся логика — внешний воркер + result-callback в `inbox.queue`.
**Источник:** [Anthropic Message Batches Announcement](https://www.anthropic.com/news/message-batches-api), [Batch processing docs](https://platform.claude.com/docs/en/build-with-claude/batch-processing), [agentbus async workloads guide](https://agentbus.sh/posts/how-to-use-the-anthropic-message-batches-api-for-async-workloads/).

---

### 4. DeepSeek implicit context caching + off-peak — реальная стоимость −95% для дев-тасков
**Что:** DeepSeek **по умолчанию** включает Context Caching on Disk у всех. С 2026/4/26 кэш-хит стоит 1/10 от исходной цены — **$0.028/1M токенов** на cache-hit input для V4-Flash (это ~100× дешевле Claude Sonnet input).
**Как:**
```json5
// openclaw.json — добавить deepseek как fallback для дешёвых задач
{
  "auth": {
    "profiles": [
      {"id": "deepseek-flash", "provider": "deepseek",
       "apiKey": "${DEEPSEEK_API_KEY}", "model": "deepseek-chat-flash"}
    ]
  },
  "agents": {
    "list": [
      {"id": "code-grunt",
       "model": {
         "primary": "deepseek-chat-flash",
         "fallbacks": ["claude-haiku-4-5"]
       }}
    ]
  }
}
```
**Off-peak часы 16:30–00:30 UTC** — исторически дополнительные −50-75% (для V3/R1; для V4 проверять актуально).
**Экономия:** на cache-hit dev-задачах (повторяющиеся code-edits, refactor-loops) — **−95%** относительно Claude.
**Подвох:** только prefix cache-hit (если префикс отличается хоть на 1 токен — miss). Качество V4-Flash хуже Sonnet — годится для код-grunt, не для архитектуры.
**Источник:** [DeepSeek Context Caching on Disk announcement](https://api-docs.deepseek.com/news/news0802), [DeepSeek pricing details](https://api-docs.deepseek.com/quick_start/pricing-details-usd), [Context Caching guide](https://api-docs.deepseek.com/guides/kv_cache).

---

### 5. Gemini 2.5 implicit caching через OpenRouter — −75% без настройки
**Что:** OpenRouter добавил автоматический implicit caching для Gemini 2.5 Pro/Flash. **Никаких breakpoints, никакой настройки** — кэшируется автоматически, как у OpenAI.
**Как:**
```json5
{
  "agents": {
    "list": [
      {"id": "long-context-reader",
       "model": {"primary": "google/gemini-2.5-flash"},
       "via": "openrouter"}
    ]
  }
}
```
**Экономия:** cache-hit стоит **0.25×** оригинала → **−75%** автоматически. Никаких cache-write costs, никаких storage costs.
**Подвох:** минимум **1028 токенов** для Flash, **2048** для Pro чтобы попасть под кэш. TTL — в среднем 3-5 минут (короче, чем у Anthropic-long). Для агентских циклов с быстрыми итерациями — идеально; для редких heartbeats — нет.
**Источник:** [OpenRouter Gemini implicit caching announcement](https://x.com/OpenRouterAI/status/1920663205380321494), [OpenRouter Prompt Caching docs](https://openrouter.ai/docs/guides/best-practices/prompt-caching).

---

### 6. `lightContext: true` + `isolatedSession: true` для всех heartbeats — −95% heartbeat-токенов
**Что:** native heartbeat в OpenClaw по умолчанию шлёт **полный контекст агента** включая всю историю сессии. Это **major token sink** (Discussion #11042 от инженеров Memori). Два флага меняют картину.
**Как:**
```json5
{
  "heartbeat": {
    "intervalMinutes": 30,
    "lightContext": true,        // только HEARTBEAT.md, без bootstrap
    "isolatedSession": true,     // отдельный transcript, без основной истории
    "model": "claude-haiku-4-5", // ← здесь МОЖНО Haiku, не Sonnet
    "maxTokens": 800             // hard cap на output
  }
}
```
**Экономия:** **с ~100K токенов на run до ~2-5K** = **−95%** heartbeat-расходов.
**Подвох:** известный баг #43767 — `lightContext: true` иногда **игнорируется** и грузит full context. Workaround: вынести heartbeat в отдельный cron-job через `openclaw-mem` или внешний скрипт. Также Issue #64795 — `isolatedSession: true` молча переиспользует тот же transcript-файл между runs (накопление). Решение: rotate transcript file by date.
**Источник:** [Native heartbeat token sink discussion #11042](https://github.com/openclaw/openclaw/discussions/11042), [Issue #43767 lightContext ignored](https://github.com/openclaw/openclaw/issues/43767), [Issue #64795 isolatedSession transcript bug](https://github.com/openclaw/openclaw/issues/64795).

---

### 7. Heartbeat вместо crons для batched checks — −80% API-вызовов
**Что:** не делай 12 кронов «проверь почту, проверь календарь, проверь Telegram, ...» — каждый запускает отдельный полноценный agent run с системным промптом. Сделай **один heartbeat**, в котором агент сам решает что проверить.
**Как:**
```yaml
# было: 12 cron-jobs × 4 раза в час = 48 runs/час
crons:
  - "*/15 * * * *  check-email"
  - "*/15 * * * *  check-calendar"
  ...

# стало: 1 heartbeat × 4 раза в час = 4 runs/час
heartbeat:
  intervalMinutes: 15
  lightContext: true
```
В HEARTBEAT.md — список «что обходить, в каком порядке, при каких условиях вызвать tools».
**Экономия:** **−80% API-вызовов**, потому что batched-checks делятся одним system-prompt токенизацией и одним model warmup-ом.
**Подвох:** теряется precise timing. Если задача требует «ровно в 09:00 отправить отчёт» — оставь крон. Если «иногда в течение часа проверить, нет ли нового» — heartbeat.
**Источник:** [Heartbeats vs cron lumadock guide](https://lumadock.com/tutorials/openclaw-heartbeat-vs-cron-vps), [How to Reduce OpenClaw API Costs by 80%](https://openclawai.io/blog/reduce-openclaw-api-costs/).

---

### 8. Token bucket per-user + дневной cap через `auth.cooldowns` — защита от runaway сессии
**Что:** в OpenClaw **нет встроенных spending caps** (это подтверждено в [api-usage-costs.md](https://docs.openclaw.ai/reference/api-usage-costs.md)). Один agent-loop с зацикленным tool-call за час может сжечь $50+. Защита — внешний rate-limiter перед gateway.
**Как (рекомендуемая схема):**
1. Для каждой channel-сессии — счётчик токенов в Redis
2. На gateway-level — middleware, считающее input+output
3. Дневной cap $5 / часовой $0.50 — при превышении возвращать «cooling down»

```python
# простой middleware для openclaw-gateway (псевдо-код)
async def token_budget_middleware(req, next):
    user_id = req.session.user_id
    spent_today = await redis.get(f"spent:{user_id}:{today}")
    if spent_today and float(spent_today) > DAILY_CAP_USD:
        return error("budget_exhausted", retry_at=midnight_utc)
    res = await next(req)
    cost = estimate_cost(res.usage)
    await redis.incrbyfloat(f"spent:{user_id}:{today}", cost)
    return res
```

Дополнительно — настроить `auth.cooldowns` чтобы при rate-limit ошибке не было бесконечного retry:
```json5
{
  "auth": {
    "cooldowns": {
      "billingBackoffHours": 5,           // при billing-error ждать 5ч
      "rateLimitedProfileRotations": 2,   // только 2 попытки rotate
      "overloadedProfileRotations": 3
    }
  }
}
```
**Экономия:** защита от $500-3600 horror story. Не «экономия» в обычном смысле, а insurance.
**Подвох:** token-counting на gateway ≠ реальный billing провайдера (особенно при cache-hit). Лучше использовать `usage.input_tokens`, `cache_read_tokens` из ответа провайдера.
**Источник:** [LLM Rate Limiting Hivenet](https://www.hivenet.com/post/llm-rate-limiting-quotas), [LiteLLM Budgets & Rate Limits](https://docs.litellm.ai/docs/proxy/users), [OpenClaw model failover](https://docs.openclaw.ai/concepts/model-failover).

---

### 9. Speculative parallelism — race 2 модели, забери первый ответ — −40-60% latency для критичных вопросов
**Что:** для простых классификационных задач, где нужен быстрый ответ — отправь **параллельно** в Groq Llama 3.3 70B, Cerebras Llama 3.3 70B, и SambaNova. Возьми первый пришедший. Cerebras — 2100 t/s, SambaNova — TTFT 0.2с. **На моделях с одинаковым качеством** это даёт **−40-60% TTFT** в худшем случае без потери качества.
**Как:**
```python
async def speculative_race(prompt: str, providers=["groq", "cerebras", "sambanova"]):
    tasks = [call_provider(p, prompt) for p in providers]
    done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    for t in pending: t.cancel()
    return next(iter(done)).result()
```
**Экономия:** не денег (платишь все 3), а **latency** для UX-критичных путей (классификатор интента в Telegram, маршрутизатор в Блок 20). Платишь 3× денег, экономишь до 60% времени.
**Подвох:** платишь за **все 3 запроса**, потому что отмена после получения первого ответа на стороне провайдера часто запоздалая. Применять только на коротких prompts (классификаторы) и только на дешёвых open-source моделях ($0.50-1/M токенов).
**Источник:** [Cerebras vs Groq vs SambaNova benchmark](https://intuitionlabs.ai/articles/cerebras-vs-sambanova-vs-groq-ai-chips), [AI Speed Leaderboard 2026](https://awesomeagents.ai/leaderboards/ai-speed-latency-leaderboard/).

---

### 10. Semantic cache (GPTCache + Redis) для повторяющихся вопросов — −60% LLM-вызовов
**Что:** уровень кэша **выше** prompt caching. Embedding запроса в vector store, поиск по cosine-similarity > 0.92 → возврат закэшированного ответа. **Не зависит от prefix-equality** — ловит «как погода?» и «какая погода?» как одно.
**Как:**
```python
# Redis VL semantic cache (production-ready)
from redisvl.extensions.llmcache import SemanticCache
cache = SemanticCache(
    name="openclaw_q_cache",
    redis_url="redis://localhost:6379",
    distance_threshold=0.08,  # cosine distance < 0.08 = match
    ttl=3600
)
# в gateway middleware:
hit = cache.check(prompt=user_msg)
if hit:
    return hit[0]["response"]
result = await llm.complete(...)
cache.store(prompt=user_msg, response=result.text)
```
**Экономия:** **−40-70%** LLM API costs на воркфло с повторяющимися вопросами (FAQ-like, status-checks, daily reminders). 67% hit rate → 65% net latency improvement при 20мс embedding overhead vs 850мс LLM call.
**Подвох:** **collision risk** — semantic match может вернуть НЕ тот ответ, который сейчас релевантен (если контекст изменился). Для агентов с time-sensitive данными (текущая погода, текущий курс) — DISABLE на этих категориях. Используй prefix `cache:` в ключе для time-sensitive данных и обнуляй TTL агрессивно.
**Источник:** [Semantic Caching for LLMs Redis](https://redis.io/blog/what-is-semantic-caching/), [PyImageSearch FastAPI+Redis semantic cache](https://pyimagesearch.com/2026/04/27/semantic-caching-for-llms-fastapi-redis-and-embeddings/), [GPTCache repo](https://github.com/zilliztech/GPTCache).

---

### 11. LLMLingua-2 prompt compression — −50-90% токенов в system prompt с потерей <2%
**Что:** Microsoft Research, маленькая модель (BERT-class) удаляет «неважные» токены из больших промптов. До **20× compression** с минимальной потерей качества. На GSM8K — потеря 1.5% при 20×.
**Как:**
```python
# pip install llmlingua
from llmlingua import PromptCompressor
compressor = PromptCompressor(model_name="microsoft/llmlingua-2-xlm-roberta-large-meetingbank",
                               use_llmlingua2=True)
compressed = compressor.compress_prompt(
    SYSTEM_PROMPT_LARGE,    # 25K токенов SOUL.md + AGENTS.md + skills
    rate=0.5,                # сжать до 50%
    force_tokens=['\n', '.', '?']   # сохранить структуру
)
# compressed.compressed_prompt — отправлять в API
```
**Экономия:** на больших system prompts (Блок 16 multi-agent с 4-мя AGENT.md) — **−50-70% input токенов** на не-кэшируемых частях. На длинных RAG-контекстах — **−4×** при +17% качества (LongLLMLingua).
**Подвох:** компрессор **сам по себе LLM-ish модель** — добавляет 50-200мс latency. Не годится для real-time чата. Идеально для **batch-jobs**, **heartbeats**, **cron-tasks**, где latency не критична. Также: ломает prompt caching (output-токены каждый раз другие). Стратегия: компрессить **до** того, как сохранить как cacheable static.
**Источник:** [LLMLingua Microsoft Research](https://www.microsoft.com/en-us/research/blog/llmlingua-innovating-llm-efficiency-with-prompt-compression/), [LLMLingua repo](https://github.com/microsoft/LLMLingua), [PromptHub LLMLingua guide](https://www.prompthub.us/blog/compressing-prompts-with-llmlingua-reduce-costs-retain-performance).

---

### 12. Model distillation — fine-tune Haiku на трейсах Sonnet → 13-24× дешевле
**Что:** прогоняешь продакшен через Sonnet/Opus, собираешь высококачественные input→output пары, fine-tune-ишь Haiku на них. Дальше Haiku-FT решает 80% задач **в 13-24 раза дешевле**.
**Как (через OpenAI Distillation API или Anthropic FT):**
1. Включить `metadata.store: true` на запросах к Sonnet — собирается traces
2. Фильтр: только запросы с user-feedback ≥ 4/5 (или прошедшие eval-проверку)
3. Запустить fine-tune job на 1000+ examples
4. Заменить primary в OpenClaw config:
```json5
{"model": {
  "primary": "ft:claude-haiku-4-5:user:openclaw-domain:abc123",
  "fallbacks": ["claude-sonnet-4-6"]
}}
```
**Экономия:** GPT-4o-mini-FT — **13.7×** lower cost-per-success vs GPT-4o; Gemini Flash Lite-FT — **24.1×**. Tensorzero benchmarks: **5-30×** cheaper inference на task-specific SLM.
**Подвох:** **synthetic data из traces работает лучше прямых traces** — на +26 percentage points точности (Tensorzero). Лучшая стратегия: GPT/Sonnet генерирует не сырой output, а edge-cases/variations поверх собранных traces. Также: FT-модель плохо генерализуется — для новых типов задач Sonnet-fallback обязателен.
**Источник:** [Tensorzero Distillation 5-30x cheaper](https://www.tensorzero.com/blog/distillation-programmatic-data-curation-smarter-llms-5-30x-cheaper-inference/), [OpenAI Distillation cookbook](https://cookbook.openai.com/examples/leveraging_model_distillation_to_fine-tune_a_model).

---

### 13. System prompt deduplication для multi-agent (Блок 16) — bytes-identical prefix → 100% cache hit
**Что:** в архитектуре с 4 агентами (Орёл/Сова/Лисица/Капибара из Блока 16) каждый имеет свой AGENT.md, но если базовая часть не **bytes-identical**, кэш не работает между ними даже на одинаковых стартовых блоках.
**Как:**
1. Вынести общую часть в shared `BASE.md` (~5K токенов)
2. **Pre-render** один раз при старте gateway, передавать **те же байты** всем 4 агентам через shared parameter (Claude Code multi-agent pattern)
3. Каждый AGENT.md = только delta поверх BASE
4. Никаких feature-flags, ENV-vars, timestamps в BASE — иначе при warmup байты разъезжаются

```python
# в openclaw plugin layer:
BASE_BYTES = render_base_md_once()   # ВЫЗЫВАТЬ РАЗ при старте
def build_system_for(agent_id):
    return BASE_BYTES + "\n\n" + AGENT_DELTAS[agent_id]   # без re-render
```
**Экономия:** при 4 агентах с 80K токенов общего BASE — **−75% input cost** при первом утреннем разогреве (один write, четыре read из cache). Cache hit-rate с 50-70% до 95%+.
**Подвох:** один бит расхождения = busted cache. Особо опасно: feature-flag warmup, generator-вызывающий time.now(), random IDs в шаблоне. Решение: явно сериализовать в bytes и логировать hash.
**Источник:** [Arize: Context management in agent harnesses](https://arize.com/blog/context-management-in-agent-harnesses), [Don't Break the Cache: Eval Prompt Caching for Long-Horizon Agents](https://arxiv.org/html/2601.06007v1).

---

### 14. `contextPruning.mode: "cache-ttl"` — авто-удаление tool results по истечении кэша
**Что:** скрытая фича OpenClaw. Когда tool-result выпадает из кэшируемого окна, дальше держать его в контексте бессмысленно — он уже стоит full price каждый turn. Эта опция удаляет tool-results ровно когда они выходят из cache TTL.
**Как:**
```yaml
agents:
  defaults:
    contextPruning:
      mode: "cache-ttl"          # удалять tool-results когда кэш истёк
      keepLastN: 3                # но всегда оставить последние 3 (для контекста)
```
**Экономия:** на tool-heavy агентах (с 20-30 tool calls в сессии) — **−30-50% input** на длинных диалогах, потому что старые tool-results не тащатся бесплатно «по инерции».
**Подвох:** агент **теряет** промежуточные tool-results после TTL. Если задача требует помнить, что было сделано 30 минут назад — нужен `/compact` или внешняя memory (mem0 из Блока 15). Хорошо комбинируется с Mem0: pruned tool-results автоматически уезжают в long-term memory.
**Источник:** [OpenClaw Prompt Caching reference (контекст pruning)](https://docs.openclaw.ai/reference/prompt-caching), [Context Engine concepts](https://docs.openclaw.ai/concepts/context-engine).

---

### 15. `imageMaxDimensionPx: 800` для screenshot-heavy work — −60% vision-токенов
**Что:** OpenClaw по умолчанию downscale-ит images до 1200px. Для большинства agent-tasks (read button, parse error message) хватает **800px**, что снижает vision-токены пропорционально площади.
**Как:**
```yaml
agents:
  defaults:
    imageMaxDimensionPx: 800     # вместо 1200
    # Для специфичных задач (OCR мелкого текста) override per-agent:
agents:
  list:
    - id: ocr-agent
      imageMaxDimensionPx: 1600  # тут нужно качество
```
**Экономия:** vision-токены пропорциональны площади. 800² / 1200² = **0.44** → **−56% vision-input**. Для агента с 10 screenshot/день — это $5-15 в месяц.
**Подвох:** мелкий текст (UI лейблы 10px, далёкие объекты) теряется. Тестируй на реальных скринах **до** включения в проде. Альтернатива: pre-process на стороне клиента — crop до релевантного региона + 1200px.
**Источник:** [OpenClaw token use](https://docs.openclaw.ai/reference/token-use), Anthropic vision pricing — токены = ceil(width × height / 750).

---

### 16. aiohttp transport вместо httpx в gateway — −97% median latency на high-concurrency
**Что:** LiteLLM benchmark — переход с httpx на aiohttp дал **−97% median latency** при концурентных запросах. У httpx connection pool default 100 connections — становится боттлнеком на высокой нагрузке.
**Как:**
```python
# в openclaw-gateway или твоём прокси
import aiohttp
connector = aiohttp.TCPConnector(
    limit=300,                    # вместо 100
    limit_per_host=50,
    keepalive_timeout=120,        # держать TCP открытыми 2 мин
    ttl_dns_cache=300,
    use_dns_cache=True
)
session = aiohttp.ClientSession(connector=connector)
```
Для httpx если не хочешь менять:
```python
limits = httpx.Limits(max_connections=300, max_keepalive_connections=100,
                       keepalive_expiry=120)
```
**Экономия:** **−97% median latency** на 1000+ concurrent requests (LiteLLM PR #11097). Не деньги, но UX и throughput для multi-user сценариев.
**Подвох:** aiohttp плохо обрабатывает HTTP/2 (Anthropic / OpenAI используют HTTP/2). Если твой workflow в основном — **редкие большие запросы** (chat) — преимущество минимально. Если **много мелких** (parallel tools, batched embeddings) — обязательно.
**Источник:** [LiteLLM aiohttp transport PR #11097](https://github.com/BerriAI/litellm/pull/11097), [HTTPX Resource Limits](https://www.python-httpx.org/advanced/resource-limits/).

---

### 17. Local Llama 3.2 1B как guardrail/router перед main LLM — −20-40% main-LLM-вызовов
**Что:** запустить Llama 3.2 1B локально (через llama.cpp или Ollama) на VPS как **первичный фильтр**. Отвечает на простые вопросы, классифицирует интент, отбраковывает spam/abuse — **до** того, как запрос пойдёт в дорогой Sonnet.
**Как:**
```yaml
# docker-compose.yml дополнительно
services:
  llama-router:
    image: ollama/ollama:latest
    volumes: ["./ollama:/root/.ollama"]
    ports: ["11434:11434"]
    deploy:
      resources:
        limits: {memory: 2G, cpus: '2'}
    command: sh -c "ollama pull llama3.2:1b && ollama serve"
```
В openclaw plugin — middleware:
```python
async def router_middleware(req):
    intent = await ollama_classify(req.message,
                                    classes=["chat", "code", "tool", "trivial"])
    if intent == "trivial":
        return await ollama_answer(req.message)   # 1B справится
    elif intent == "tool":
        req.model_override = "claude-haiku-4-5"   # tools через Haiku
    # else default Sonnet
```
**Экономия:** **−20-40% main-LLM вызовов** для агента в Telegram (много trivial: «спасибо», «понял», «ок»). Llama 3.2 1B int4 — **0.5GB RAM**, работает даже на $5 VPS.
**Подвох:** false-positive «trivial» (1B неправильно классифицирует серьёзный запрос как trivial) → плохой UX. Решение: classifier с порогом confidence > 0.85, иначе fallback на main LLM. Также: 1B жрёт CPU — на VPS с 1 vCPU будет сильно лагать (надо 2+ vCPU).
**Источник:** [Llama 3.2 1B HuggingFace](https://huggingface.co/meta-llama/Llama-3.2-1B), [Local Router AI-Agent guide](https://www.hackster.io/shahizat/building-a-local-router-ai-agent-with-n8n-and-llama-cpp-5080d8), [llama.cpp router mode](https://huggingface.co/blog/ggml-org/model-management-in-llamacpp).

---

### 18. Async parallel tool calling в OpenClaw — −40-70% latency на multi-tool turns
**Что:** OpenClaw по умолчанию выполняет tools **последовательно**. Если агент в одном turn вызывает 4 независимых tool-а (read_email + read_calendar + read_telegram + read_obsidian) — 4× по 300мс = 1.2с. Параллельно — ~300мс.
**Как:** в большинстве OpenClaw plugins tool-execution идёт через `await tool.run()`. Wrap в `asyncio.gather`:
```python
# в плагине, который собирает tool_use blocks из ассистента:
async def execute_tool_calls(tool_uses):
    independent = [t for t in tool_uses if not has_data_dependency(t, tool_uses)]
    dependent = [t for t in tool_uses if t not in independent]

    # параллельно — независимые
    independent_results = await asyncio.gather(
        *[t.run() for t in independent], return_exceptions=True
    )
    # последовательно — зависимые (используют output друг друга)
    dependent_results = []
    for t in dependent:
        dependent_results.append(await t.run())
    return independent_results + dependent_results
```
**Экономия:** **−40-70% latency** на multi-tool turns. Benchmarks LLMCompiler — 1.4-2.4×, иногда 3.7×. SimpleTool — 3-6× end-to-end speedup.
**Подвох:** **state mutations** ломают параллелизм — если tool изменяет shared state, который читает другой tool, нужна dependency analysis. Также: токены те же (платишь за весь output модели), но UX-time меньше.
**Источник:** [Why Parallel Tool Calling Matters](https://www.codeant.ai/blogs/parallel-tool-calling), [SimpleTool: Parallel Decoding](https://arxiv.org/abs/2603.00030), [DEV.to Parallel Tool Calling complete guide](https://dev.to/rahulxsingh/parallel-tool-calling-in-llm-agents-complete-guide-with-code-examples-3ilo).

---

### 19. Dedicated TTFT-провайдер для интерактивного chat — Cerebras/SambaNova → −80% perceived latency
**Что:** для **интерактивных** Telegram-сессий главное — TTFT (time to first token), не итоговая длина. SambaNova даёт **TTFT 0.2с** на Llama 3.3 70B (vs 0.6-1.5с у Anthropic/OpenAI). Cerebras — 2100 t/s output.
**Как:** настроить в OpenClaw отдельный «hot-path» агент:
```json5
{
  "agents": {
    "list": [
      {"id": "telegram-fast",
       "model": {
         "primary": "llama-3.3-70b@cerebras",     // быстрый старт
         "fallbacks": ["claude-haiku-4-5"]
       },
       "channels": ["telegram"],
       "blockStreaming": true,
       "blockStreamingBreak": "text_end"
      }
    ]
  }
}
```
**Экономия:** не денег (платишь по token-rate, у Cerebras сравнимо), а **UX**: пользователь видит первое слово через 200мс вместо 1.5с — perceived latency **−80%**. Для Telegram-бота это критично.
**Подвох:** Cerebras и SambaNova — **только open-source модели** (Llama, Qwen). Если задача требует Sonnet-уровня reasoning — fallback на Anthropic, и тогда TTFT будет средний. Качество Llama 3.3 70B хуже Sonnet 4.6 на сложных задачах.
**Источник:** [SambaNova vs Groq inference face-off](https://sambanova.ai/blog/sambanova-vs-groq), [Cerebras CS-3 vs Groq LPU](https://www.cerebras.ai/blog/cerebras-cs-3-vs-groq-lpu), [Tokens Per Second LLM Speed Benchmark 2026](https://www.morphllm.com/tokens-per-second).

---

### 20. Telegram typing indicator — keepalive 4 сек с двойной защитой от зависания
**Что:** Telegram typing indicator живёт **5 секунд**. LLM-call обычно 10-60 сек. Без keepalive — пользователь видит «бот молчит». **С плохим keepalive** — баг #27177 OpenClaw: typing-indicator висит вечно после завершения agent run.
**Как (production-pattern):**
```python
async def with_typing(bot, chat_id, coro):
    stop_event = asyncio.Event()
    completed = asyncio.Event()

    async def keepalive():
        while not stop_event.is_set():
            try:
                await bot.send_chat_action(chat_id, "typing")
            except Exception: pass
            try:
                await asyncio.wait_for(stop_event.wait(), timeout=4.0)
            except asyncio.TimeoutError: continue

    ka_task = asyncio.create_task(keepalive())
    try:
        result = await coro
        return result
    finally:
        stop_event.set()
        completed.set()
        await ka_task   # ВАЖНО: ждать завершения, иначе loop переживёт run
```
**Экономия:** не денег. UX: пользователи **в 2-3 раза реже** жмут «отправить ещё раз» (что приводит к двойным billable runs).
**Подвох:** Issue #27177 — без явного `stop_event.set()` при exception, loop живёт. Двойная защита: `asyncio.shield` для основной coro + finally-cleanup.
**Источник:** [OpenClaw Issue #27177 typing indicator persists](https://github.com/openclaw/openclaw/issues/27177), [Python-telegram-bot ChatAction TYPING](https://github.com/python-telegram-bot/python-telegram-bot/issues/2869).

---

### 21. DeepInfra / Together Llama 3.3 70B как fallback-цепочка — −74% vs Sonnet
**Что:** не очевидно, но цены на Llama 3.3 70B сильно различаются между провайдерами. DeepInfra — **$0.23 input / $0.40 output** за 1M. Together — $0.88/$0.88. Fireworks — $0.90/$0.90.
**Как (cost-optimal fallback chain):**
```json5
{"agents": {"defaults": {"model": {
  "primary": "claude-sonnet-4-6",
  "fallbacks": [
    "claude-haiku-4-5",                           // если Sonnet rate-limit
    "llama-3.3-70b@deepinfra",                    // если Anthropic billing
    "llama-3.3-70b@fireworks"                     // если deepinfra down
  ]
}}}}
```
**Экономия:** при срабатывании fallback на DeepInfra — **−74%** относительно Sonnet ($0.23 vs $3 input). Для длинных fallback-периодов (Anthropic billing-error до 24ч экспоненциальный backoff) — кардинально меняет картину.
**Подвох:** Llama-output ≠ Sonnet-output в формате. JSON-mode/tool-use схемы могут не совпадать. Решение: использовать LiteLLM proxy или OpenRouter-универсальный layer, который нормализует tool-use schema. Также: качество Llama хуже на long-context tasks.
**Источник:** [Llama 3.3 70B providers comparison Artificial Analysis](https://artificialanalysis.ai/models/llama-3-3-instruct-70b/providers), [Fireworks AI Review 99.8% uptime $0.90/M](https://tokenmix.ai/blog/fireworks-ai-review), [Llama 3.3 70B 2026 pricing TokenMix](https://tokenmix.ai/blog/llama-3-3-70b).

---

### 22. Token golf для SOUL.md/AGENTS.md — −30-50% размера без потери качества
**Что:** конкретные приёмы, которыми инженеры Anthropic-style prompting сокращают системные промпты:

| Приём | Пример | Экономия |
|---|---|---|
| Markdown-bullets вместо плотной прозы | "Ты должен..." → "- Action 1\n- Action 2" | −20% |
| YAML вместо JSON в примерах | `key: value` вместо `"key": "value"` | −15% |
| Сокращённые имена параметров в tool-defs | `{"q": "..."}` вместо `{"query": "..."}` | −5% |
| Удаление вежливости («пожалуйста», «спасибо») | LLM не нужно — он не обижается | −3-5% |
| One-shot example вместо two-shot | Часто хватает одного хорошего | −10-20% |
| Англ вместо рус для tool-имен и системы | Все frontier models тренированы на en | −10-15% (русский ~1.5 токена/символ vs английский 0.25) |
| Удаление xml-тегов где hierarchy ясна из markdown | `<thinking>` если уже есть `## Thinking` | −5% |

**Как (применение к OpenClaw):** вынести heavy-русский content в **Memory** (который грузится только при необходимости через retrieval), оставить в SOUL.md только английский core-instructions.

**Экономия:** на средне-сложном AGENT.md (8K токенов) — **−30-50% размера** = **−$3-5/мес** на cache-write costs (важно при 1h TTL — каждый cache-write 2× input).
**Подвох:** некоторые модели хуже работают с английским при том, что пользователь пишет на русском. Тестировать на golden-set перед миграцией.
**Источник:** Anthropic prompting best practices, [Mastering Claude Prompt Caching 2025](https://sparkco.ai/blog/mastering-claude-prompt-caching-techniques-for-2025).

---

## ⚡ Latency tuning — топ-10 скрытых рычагов

### L1. HTTP/3 (QUIC) для Anthropic/OpenAI — −20-50% setup time
**Что:** Anthropic API за Cloudflare → поддерживает HTTP/3. Большинство Python-клиентов **не используют** HTTP/3 по умолчанию.
**Как:** `pip install httpx[http2,brotli]` + переход на `aioquic` (если критично):
```python
client = httpx.AsyncClient(http2=True)  # минимум — HTTP/2
# для HTTP/3 — экспериментально через aioquic transport
```
**Эффект:** **−25-50% setup time** на интерконтинентальных connections (US East → EU server). Особо заметно в первом запросе после простоя.
**Подвох:** HTTP/3 поверх UDP — некоторые корпоративные NAT/firewall блокируют. На VPS Hetzner FSN1 — работает, на проде с GFW-подобным фильтром — нет.
**Источник:** [Zuplo HTTP/2 HTTP/3 API Performance](https://zuplo.com/learning-center/enhancing-api-performance-with-http-2-and-http-3-protocols).

---

### L2. DNS over HTTPS на VPS в РФ + локальный resolver — −30-100мс на DNS lookup
**Что:** на типичных VPS (Beget, Reg.ru) дефолтный resolver — провайдерский, часто медленный (50-200мс). DoH через 1.1.1.1 / Google + локальный кэш — 1-5мс.
**Как:**
```bash
# /etc/systemd/resolved.conf.d/doh.conf
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 8.8.8.8#dns.google
DNSOverTLS=yes
DNSStubListener=yes
Cache=yes
CacheFromLocalhost=yes
```
Или AdGuard Home / Unbound на 127.0.0.1.
**Эффект:** **−30-100мс на каждый первый запрос** к новому домену в час (api.anthropic.com → IP). При 50 запросах в день — суммарно секунды экономии latency и десятки уменьшения timeouts.
**Подвох:** в РФ Cloudflare 1.1.1.1 нестабилен — может блокироваться. Альтернатива: Yandex DNS DoH (77.88.8.88) или собственный Unbound на VPS-локально.
**Источник:** [DNS-over-HTTPS performance ThousandEyes](https://www.thousandeyes.com/blog/dns-over-https-performance), [Mullvad DoH/DoT guide](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls).

---

### L3. Connection pooling 300+ keepalive в gateway — масштабируется на 100+ concurrent
**Что:** OpenClaw gateway по умолчанию использует httpx с pool=100. На 50+ active sessions с tools — bottleneck.
**Как:**
```yaml
gateway:
  http:
    maxConnections: 300
    maxKeepaliveConnections: 150
    keepaliveTimeoutMs: 120000
```
Или через ENV:
```bash
HTTPX_MAX_CONNECTIONS=300
HTTPX_MAX_KEEPALIVE=150
```
**Эффект:** на high-concurrency — **stable latency** (без скачков 200мс → 5с при wait-on-pool). LiteLLM benchmark: −97% median latency.
**Подвох:** провайдеры имеют свои rate-limits на параллельные connections (Anthropic ~50 default). 300 в pool ≠ 300 параллельных запросов к одному провайдеру.
**Источник:** [LiteLLM aiohttp PR](https://github.com/BerriAI/litellm/pull/11097), [HTTPX Limits](https://www.python-httpx.org/advanced/resource-limits/).

---

### L4. Edge-inference Cloudflare Workers AI для preprocessing — латентность 50-150мс
**Что:** для guardrail / classifier / NER preprocessing — Workers AI выполняется на ближайшем GPU-кластере Cloudflare. **Не для chat**, а для микро-задач до основного LLM-call.
**Как:**
```js
// cf-worker.js
export default {
  async fetch(req, env) {
    const text = (await req.json()).text;
    const result = await env.AI.run('@cf/meta/llama-3.2-1b-instruct',
      { prompt: `Classify: ${text}`, max_tokens: 10 });
    return Response.json(result);
  }
}
```
В OpenClaw — middleware вызывает Worker до основного LLM.
**Эффект:** **50-150мс** на классификацию vs 800мс через Anthropic. Для intent-routing в Telegram — экономит 600мс perceived TTFT.
**Подвох:** GPU-кластеры **не в каждом из 300+ Cloudflare locations**, а централизованы. SLA нет — для critical path не годится.
**Источник:** [Cloudflare Workers AI](https://workers.cloudflare.com/product/workers-ai), [Workers AI alternatives 2026](https://tokenmix.ai/blog/cloudflare-workers-ai-alternatives-llm-inference-2026).

---

### L5. DeepSeek MTP speculative decoding — 1.8× speedup output
**Что:** DeepSeek V3+ имеет встроенный MTP (Multi-Token Prediction) — модель предсказывает несколько токенов вперёд параллельно. Acceptance rate >80% → **1.8× throughput** на output.
**Как:** **включается автоматически** в DeepSeek API (`deepseek-chat`, `deepseek-reasoner`). На self-hosted (vLLM / SGLang) — флаг `--enable-mtp`.
**Эффект:** **−40-45% времени** на длинные выводы (1000+ токенов output). Особо заметно на reasoning/code tasks.
**Подвох:** acceptance rate падает на нестандартных доменах (юр-текст, узкоспециальный код) → effective speedup только 1.2-1.4×. Качество не страдает (verification всё равно с main model).
**Источник:** [DeepSeek-V3 Technical Report MTP](https://arxiv.org/html/2412.19437v1), [DeepSeek MTP DeepWiki](https://deepwiki.com/deepseek-ai/DeepSeek-V3/4.4-multi-token-prediction-(mtp)), [SGLang MTP tutorial](https://rocm.docs.amd.com/projects/ai-developer-hub/en/latest/notebooks/inference/mtp.html).

---

### L6. Block streaming в OpenClaw с `text_end` break — perceived latency −60%
**Что:** OpenClaw block streaming имеет два режима: `message_end` (буфер до конца) и `text_end` (отдавать сразу как закончился text-block). По умолчанию — `off` (не стримит вообще).
**Как:**
```yaml
agents:
  defaults:
    blockStreamingDefault: "on"
    blockStreamingBreak: "text_end"
    blockStreamingChunk:
      minChars: 80
      maxChars: 400
      breakPreference: "sentence"
```
**Эффект:** в Telegram пользователь видит первое сообщение **сразу как готов первый параграф** (0.5-1с), а не после полного ответа (8-15с). Perceived TTFT **−60-80%**.
**Подвох:** Telegram имеет свои limits (`maxMessageLength` 4096) — chunking должен учитывать. Также: `blockStreamingCoalesce` (`maxChars`, `idleMs`) может склеить chunks обратно — настраивай аккуратно.
**Источник:** [OpenClaw Streaming concepts](https://docs.openclaw.ai/concepts/streaming).

---

### L7. Pre-warm cache через cron-discovery каждый час — нулевой TTFT на горячие запросы
**Что:** classic технику cache pre-warming никто не использует для LLM. Идея: за 5 минут **до** ожидаемого активного use (например, утром в 08:55) cron-job делает 1 запрос к main agent с полным system-prompt — это создаёт cache-write. К 09:00 пользователь получает cache-hit с TTFT 50-100мс вместо 800мс.
**Как:**
```yaml
crons:
  - id: cache-warmer
    schedule: "55 8,12,17 * * *"   # перед утром, обедом, вечером
    agent: main
    prompt: "Ping (cache warmup)"
    maxTokens: 10
```
**Эффект:** **−700мс TTFT** на первый запрос пользователя в каждом окне. Стоимость warmup: ~$0.02 (одна короткая cache-write).
**Подвох:** TTL Anthropic 1h = надо warmup каждые 55 минут (не каждые 5). DeepSeek implicit — TTL короче, warmup каждые 3-5 минут (стоимость растёт).
**Источник:** общая практика prompt caching, описано в [How We Cut LLM Costs by 59% with Prompt Caching ProjectDiscovery](https://projectdiscovery.io/blog/how-we-cut-llm-cost-with-prompt-caching).

---

### L8. Reduce `imageMaxDimensionPx` + crop-server-side — −50% vision TTFT
**Что:** не только токены (см. техника #15), но и **vision pre-processing latency**. Anthropic тратит 200-500мс на image-encoding в зависимости от размера.
**Как:** перед отправкой — server-side crop через PIL до релевантной области:
```python
from PIL import Image
img = Image.open(input_path)
# crop до bbox если знаешь где интересный регион
img.crop((x1, y1, x2, y2)).resize((800, int(800 * h/w))).save(out_path)
```
**Эффект:** **−50% vision-TTFT** + меньше токенов. Для скринов с конкретной кнопкой — exponential reduction.
**Подвох:** требует knowledge о bbox. Для full-screen screenshots без приоритетного региона — просто resize до 800px.
**Источник:** Anthropic vision processing latency analysis (anecdotal industry).

---

### L9. SSE keepalive heartbeat для long-running streams — против idle-timeout
**Что:** некоторые long-running агенты (Опус с deep thinking) могут «молчать» 30-60 секунд. nginx / Cloudflare proxy дефолтно убивают idle-connections через 60с. Решение: SSE keep-alive comments каждые 15-20с.
**Как:** в gateway-streaming layer добавить:
```python
async def stream_with_keepalive(coro):
    last_event = time.monotonic()
    async for chunk in coro:
        yield chunk
        last_event = time.monotonic()
    # параллельно — keepalive task:
    while not done.is_set():
        if time.monotonic() - last_event > 15:
            yield ":\n\n"   # SSE comment
        await asyncio.sleep(2)
```
**Эффект:** prevents 504 Gateway Timeout на долгих thinking-инференсах. Не latency-экономия, а **reliability** — без неё пользователь видит «error» где должен быть ответ.
**Подвох:** некоторые SSE-парсеры на клиенте не любят commented-only events. Тестировать на Telegram, web-UI, Slack.
**Источник:** [Anthropic Streaming Messages docs](https://docs.anthropic.com/en/api/streaming).

---

### L10. Workspace-level prompt cache isolation (Anthropic Feb 2026 change)
**Что:** с **5 февраля 2026** Anthropic переключил cache isolation с org-level на workspace-level. Если у тебя несколько workspace под одной org — между ними кэш **не шарится**. До этого — шарился.
**Как (новая стратегия):** для multi-tenant сценариев — **один workspace на product**, не один на клиента. Если у тебя 4 агента из Блока 16 (multi-agent) — все в **одном** workspace, чтобы prefix-кэш делился.
```bash
# в Anthropic Console — создать workspace "openclaw-main"
# и использовать API-ключ ТОЛЬКО этого workspace для всех агентов
```
**Эффект:** **−25-50% cache-write costs** при правильной workspace-структуре (vs неправильной, где кэш фрагментирован).
**Подвох:** для b2b multi-tenant — наоборот, нужна изоляция (per-customer workspace) и приходится платить за дублированный cache-write.
**Источник:** [Anthropic Prompt Caching docs — workspace isolation Feb 2026](https://platform.claude.com/docs/en/build-with-claude/prompt-caching).

---

## 🎯 Production-ready cost optimization stack — copy-paste конфиг

Готовый комплект для personal-агента OpenClaw. Применять **итеративно** (по одному параметру в день, проверять метрики).

```json5
// /opt/openclaw/openclaw.json (production cost-optimized)
{
  "auth": {
    "profiles": [
      {"id": "anthropic-main", "provider": "anthropic",
       "apiKey": "${ANTHROPIC_API_KEY}", "workspace": "openclaw-main"},
      {"id": "deepseek", "provider": "deepseek", "apiKey": "${DEEPSEEK_API_KEY}"},
      {"id": "openrouter", "provider": "openrouter", "apiKey": "${OPENROUTER_API_KEY}"}
    ],
    "cooldowns": {
      "billingBackoffHours": 5,
      "rateLimitedProfileRotations": 2,
      "overloadedProfileRotations": 3
    }
  },

  "agents": {
    "defaults": {
      "model": {
        "primary": "claude-sonnet-4-6",
        "fallbacks": [
          "claude-haiku-4-5",
          "deepseek-chat-flash",
          "google/gemini-2.5-flash@openrouter"
        ]
      },
      "params": {
        "cacheRetention": "long",          // 1h TTL
        "cacheBreakpoints": 4              // все 4 точки
      },
      "contextPruning": {
        "mode": "cache-ttl",
        "keepLastN": 3
      },
      "imageMaxDimensionPx": 800,
      "blockStreamingDefault": "on",
      "blockStreamingBreak": "text_end",
      "blockStreamingChunk": {"minChars": 80, "maxChars": 400}
    },
    "list": [
      {"id": "telegram-fast",
       "model": {"primary": "claude-haiku-4-5",
                 "fallbacks": ["llama-3.3-70b@deepinfra"]},
       "channels": ["telegram"]},
      {"id": "batch-digest",
       "model": {"primary": "claude-sonnet-4-6@batch"},
       "schedule": "nightly"}
    ]
  },

  "heartbeat": {
    "intervalMinutes": 30,                 // не 5, не 15
    "lightContext": true,                  // !!! не пропустить
    "isolatedSession": true,
    "model": "claude-haiku-4-5",
    "maxTokens": 800
  },

  "gateway": {
    "http": {
      "maxConnections": 300,
      "maxKeepaliveConnections": 150,
      "keepaliveTimeoutMs": 120000,
      "http2": true
    },
    "channelHealthCheckMinutes": 5,
    "handshakeTimeoutMs": 30000
  },

  "cron": {
    "maxConcurrentRuns": 2,
    "sessionRetention": "24h",
    "runLog": {"maxBytes": "2mb", "keepLines": 2000},
    "jobs": [
      {"id": "cache-warmup",
       "schedule": "55 8,12,17,22 * * *",
       "agent": "main",
       "prompt": "ping",
       "maxTokens": 10}
    ]
  },

  "diagnostics": {
    "cacheTrace": {
      "enabled": true,
      "filePath": "~/.openclaw/logs/cache-trace.jsonl",
      "includeSystem": true
    }
  }
}
```

```yaml
# docker-compose.yml — local Llama router + Redis semantic cache
version: "3.9"
services:
  openclaw:
    image: openclaw/openclaw:latest
    env_file: .env
    volumes:
      - ./openclaw.json:/etc/openclaw/openclaw.json:ro
      - openclaw-data:/var/lib/openclaw
    depends_on: [redis, llama-router]
    networks: [openclaw-net]

  llama-router:
    image: ollama/ollama:latest
    volumes: [./ollama:/root/.ollama]
    deploy:
      resources:
        limits: {memory: 2G, cpus: '2'}
    command: sh -c "ollama pull llama3.2:1b && ollama serve"
    networks: [openclaw-net]

  redis:
    image: redis/redis-stack:latest    # с RediSearch для vector cache
    volumes: [redis-data:/data]
    networks: [openclaw-net]

volumes:
  openclaw-data:
  redis-data:

networks:
  openclaw-net:
```

```bash
# /opt/openclaw/scripts/cost-monitor.sh — простой watchdog
#!/usr/bin/env bash
set -euo pipefail
DAILY_CAP_USD=5.00
LOG="/var/log/openclaw/cost.log"

today=$(date -u +%Y-%m-%d)
spent=$(jq -r --arg d "$today" '
  [.[] | select(.ts | startswith($d))] |
  map(.cost_usd // 0) | add // 0
' "$LOG")

if (( $(echo "$spent > $DAILY_CAP_USD" | bc -l) )); then
  echo "DAILY CAP HIT: spent $spent > $DAILY_CAP_USD" | \
    curl -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT_ID" -d text=@-
  systemctl stop openclaw
fi
```

---

## 📊 Чек-лист быстрой диагностики «дорого что-то»

Если месячный счёт превысил ожидаемый — пройти по списку (порядок отражает частоту проблем):

- [ ] **Heartbeat**: `lightContext: true`? `isolatedSession: true`? Интервал ≥ 30 мин? Модель — Haiku?
- [ ] **Cache hit-rate**: проверить `~/.openclaw/logs/cache-trace.jsonl` — % hit > 80%?
- [ ] **Timestamps в system prompt**: `grep -E "Today|Now|Date" SOUL.md AGENTS.md` — найдено? Вынести в user message.
- [ ] **`/compact` запускается**? Проверить размер последних трёх сессий — растёт линейно?
- [ ] **Tool results**: один tool отдаёт 10K+ токенов? Limit-it сервер-side.
- [ ] **Workspace** — все агенты в одном Anthropic workspace?
- [ ] **Fallback chain** срабатывает? `grep "fallback_used" logs/` — если часто, primary в overload.
- [ ] **Cron-jobs** vs heartbeat — больше 5 крон-job/час? Объединить в heartbeat.
- [ ] **Vision images**: `imageMaxDimensionPx` ≤ 1200? `find . -name '*.png' -size +500k` — есть гигантские скрины?
- [ ] **Spending cap внешний** — настроен? Если нет — ставить НЕМЕДЛЕННО.

---

## 📚 Все источники (32+)

**OpenClaw официальная документация:**
1. [OpenClaw llms.txt index](https://docs.openclaw.ai/llms.txt)
2. [Prompt Caching reference](https://docs.openclaw.ai/reference/prompt-caching)
3. [Token Use](https://docs.openclaw.ai/reference/token-use)
4. [API Usage Costs](https://docs.openclaw.ai/reference/api-usage-costs)
5. [Context Engine](https://docs.openclaw.ai/concepts/context-engine)
6. [Model Failover](https://docs.openclaw.ai/concepts/model-failover)
7. [Streaming](https://docs.openclaw.ai/concepts/streaming)
8. [Gateway Configuration](https://docs.openclaw.ai/gateway/configuration)
9. [Heartbeat docs](https://docs.openclaw.ai/gateway/heartbeat)

**OpenClaw GitHub issues и discussions:**
10. [Discussion #11042: native heartbeat token sink](https://github.com/openclaw/openclaw/discussions/11042)
11. [Issue #43767: lightContext ignored](https://github.com/openclaw/openclaw/issues/43767)
12. [Issue #64795: isolatedSession transcript reuse](https://github.com/openclaw/openclaw/issues/64795)
13. [Issue #27177: Telegram typing indicator persists](https://github.com/openclaw/openclaw/issues/27177)

**Anthropic / OpenAI / Claude Code:**
14. [Anthropic Prompt Caching docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
15. [Anthropic Message Batches API announcement](https://www.anthropic.com/news/message-batches-api)
16. [Anthropic Batch Processing docs](https://platform.claude.com/docs/en/build-with-claude/batch-processing)
17. [Anthropic Streaming Messages](https://docs.anthropic.com/en/api/streaming)
18. [claude-code Issue #46829: cache TTL 1h→5m regression](https://github.com/anthropics/claude-code/issues/46829)
19. [OpenAI Batch API docs](https://developers.openai.com/api/docs/guides/batch)
20. [Spring AI Anthropic Prompt Caching 4 breakpoints](https://spring.io/blog/2025/10/27/spring-ai-anthropic-prompt-caching-blog/)

**DeepSeek / Gemini / OpenRouter:**
21. [DeepSeek Context Caching announcement](https://api-docs.deepseek.com/news/news0802)
22. [DeepSeek pricing details](https://api-docs.deepseek.com/quick_start/pricing-details-usd)
23. [DeepSeek MTP technical report](https://arxiv.org/html/2412.19437v1)
24. [OpenRouter Gemini implicit caching announcement](https://x.com/OpenRouterAI/status/1920663205380321494)
25. [OpenRouter Prompt Caching guide](https://openrouter.ai/docs/guides/best-practices/prompt-caching)

**Inference providers и benchmarks:**
26. [Cerebras vs SambaNova vs Groq comparison](https://intuitionlabs.ai/articles/cerebras-vs-sambanova-vs-groq-ai-chips)
27. [Llama 3.3 70B Artificial Analysis benchmarks](https://artificialanalysis.ai/models/llama-3-3-instruct-70b/providers)
28. [Tokens Per Second LLM Speed Benchmark 2026](https://www.morphllm.com/tokens-per-second)
29. [Cloudflare Workers AI](https://workers.cloudflare.com/product/workers-ai)

**Patterns и optimization:**
30. [Tensorzero Distillation 5-30x cheaper](https://www.tensorzero.com/blog/distillation-programmatic-data-curation-smarter-llms-5-30x-cheaper-inference/)
31. [LLMLingua Microsoft Research](https://www.microsoft.com/en-us/research/blog/llmlingua-innovating-llm-efficiency-with-prompt-compression/)
32. [GPTCache repo](https://github.com/zilliztech/GPTCache)
33. [LiteLLM aiohttp transport PR #11097 — −97% latency](https://github.com/BerriAI/litellm/pull/11097)
34. [Don't Break the Cache: Eval Prompt Caching for Long-Horizon Agents (arxiv)](https://arxiv.org/html/2601.06007v1)
35. [SimpleTool Parallel Decoding (arxiv)](https://arxiv.org/abs/2603.00030)
36. [Arize: Context management in agent harnesses](https://arize.com/blog/context-management-in-agent-harnesses)

**Community гайды (Habr / DEV.to / blogs):**
37. [Heartbeats in OpenClaw — Cheap Checks First (DEV.to)](https://dev.to/damogallagher/heartbeats-in-openclaw-cheap-checks-first-models-only-when-you-need-them-4bfi)
38. [How to Reduce OpenClaw API Costs by 80%](https://openclawai.io/blog/reduce-openclaw-api-costs/)
39. [LaoZhang Cost Optimization $600→$20](https://blog.laozhang.ai/en/posts/openclaw-save-money-practical-guide)
40. [OpenClaw Heartbeat vs Cron LumaDock](https://lumadock.com/tutorials/openclaw-heartbeat-vs-cron-vps)
41. [Habr: Прагматичный OpenClaw](https://habr.com/ru/articles/1008782/)
42. [Habr: Феномен OpenClaw](https://habr.com/ru/articles/1024744/)
43. [PyImageSearch: Semantic Caching FastAPI+Redis](https://pyimagesearch.com/2026/04/27/semantic-caching-for-llms-fastapi-redis-and-embeddings/)
44. [Hivenet: LLM Rate Limiting and Quotas](https://www.hivenet.com/post/llm-rate-limiting-quotas)
