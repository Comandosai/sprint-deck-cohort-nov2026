# Memory & Multi-agent magic — продвинутые паттерны

> Что используют те, у кого агенты живут год+ в продакшене.
> Дата: апрель 2026
> Стек: OpenClaw + Mem0/Qdrant/Cognee/Graphiti + bindings/sessions_spawn

---

## TL;DR — карта блока

Ниже 36 паттернов, разбитых на 5 групп:

1. **Память — продвинутые трюки** (1–13): эпизод/семантика/процедура, линт памяти, self-rewriting, time-aware retrieval, healing, partitions.
2. **Retrieval мастерство** (14–20): HyDE, RAG-Fusion + RRF, Step-back, Self-RAG, GraphRAG, ColBERT, RAFT.
3. **Мульти-агент** (21–28): Orchestrator-Worker, Pipeline, Mesh, Council, Adversarial Debate, Reflection, Handoffs, Agents-as-Tools.
4. **Координация и надёжность** (29–34): Blackboard, Event Sourcing, Idempotency, Saga, Circuit Breaker, Backpressure.
5. **Эвалюация и анти-паттерны** (35–36+): trace vs outcome, counterfactual, что НЕ делать.

В конце — три готовых шаблона команд под use cases Дмитрия и тренды апреля 2026.

---

## Часть 1. Память — топ-13 продвинутых паттернов

### 1. Триада Episodic + Semantic + Procedural

**Что:** разделить память агента на три когнитивных слоя — как у человека:
- **Episodic** — что произошло (журнал событий с timestamp): «5 марта 2026 пользователь подтвердил выпуск ролика про OpenClaw v2.4».
- **Semantic** — что я знаю (факты, предпочтения): «Дмитрий ведёт канал @ai_comandos», «работает в часовом поясе Москвы».
- **Procedural** — как делать (SOP, чек-листы): «Перед публикацией ролика прогнать через Yandex VOT, потом video-seo-publisher».

**Когда применять:** если у агента смешиваются «правила», «история» и «знания» в одном MEMORY.md — он начинает путаться. У длинноживущих ассистентов триада обязательна.

**Реализация под OpenClaw:**
```
~/.openclaw/agents/<agentId>/
├── MEMORY.md            # семантика (правила/personа, < 800 слов)
├── PROCEDURES.md        # процедурная память (плейбуки)
├── memory/
│   ├── episodic/2026-04-29.md   # эпизод-журнал по дате
│   └── semantic/topic-*.md       # детали по темам
└── sessions/             # native эпизодическая в OpenClaw
```
Mem0 = semantic store. Graphiti/Cognee = episodic с временной валидностью. Procedural = текстовые `.md` + skills.

**Подвох:** consolidation — путь episodic → semantic. Без него episodic растёт бесконечно. Раз в неделю запускай консолидатор: «Прочитай episodic за 7 дней, выпиши только устойчивые факты в semantic, остальное архивируй».

**Источник:** [Position: Episodic Memory is the Missing Piece for Long-Term LLM Agents (arxiv)](https://arxiv.org/pdf/2502.06975), [State of AI Agent Memory 2026 (Mem0)](https://mem0.ai/blog/state-of-ai-agent-memory-2026), [Letta — Agent Memory](https://www.letta.com/blog/agent-memory).

---

### 2. Memory Linting — автомат-проверка качества памяти

**Что:** ночной cron-агент, который читает всю память и ищет:
- **Дубли** — два факта про одно и то же разными словами.
- **Конфликты** — «Дмитрий любит чай» vs «Дмитрий пьёт только кофе».
- **Stale** — факты не обновлялись 90+ дней и не подтверждались.
- **Orphans** — факт без источника/timestamp.
- **Превышение лимитов** — MEMORY.md > 800 слов, любой файл > 20K символов.

**Когда применять:** на любом проде после первого месяца. Без линта память становится «чердаком».

**Реализация (OpenClaw cron skill):**
```yaml
# .openclaw/skills/memory-lint.md
trigger: cron "0 4 * * 0"   # каждое воскресенье 04:00
steps:
  1. Прочитать MEMORY.md, memory/semantic/*.md
  2. Для каждого факта: check_duplicates(threshold=0.92 cosine)
  3. Найти противоречия через LLM-as-judge
  4. Помечать stale: last_seen < now - 90d AND access_count < 3
  5. Записать отчёт в memory/lint-report-YYYY-MM-DD.md
  6. Спросить разрешения (proactive ping в Telegram) для удалений
```
MemOS встраивает conflict detection и dedup как часть write-pipeline.

**Подвох:** автоудаление без подтверждения = смерть проекта. Лимит — ровно 5 предложений на удаление за один прогон линта.

**Источник:** [MemOS: A Memory OS for AI System](https://statics.memtensor.com.cn/files/MemOS_0707.pdf), [Mem0 self-editing model](https://mem0.ai/blog/state-of-ai-agent-memory-2026), [Tim Kellogg — Agent Memory Patterns](https://timkellogg.me/blog/2026/04/27/memory-patterns).

---

### 3. Self-rewriting Memory (auto-MEMORY.md)

**Что:** в конце каждой сессии агент сам решает, что из текущего диалога стоит сохранить навсегда, и пишет это в MEMORY.md или semantic-store. Не пользователь нажимает «запомни», а агент сам распознаёт «это важно».

**Когда применять:** длинные ассистенты, контент-команда, личные продакшен-боты. Без этого пользователь устаёт говорить «запомни, что…».

**Реализация:**
```python
# OpenClaw on_session_end hook
def on_session_end(session):
    candidates = llm.extract_candidates(
        session.transcript,
        prompt="Выпиши ТОЛЬКО факты, которые: "
               "(a) останутся истинными через месяц, "
               "(b) пользователь произнёс утвердительно (не вопрос), "
               "(c) не дубль из MEMORY.md. "
               "Каждый факт ≤ 25 слов, формат markdown bullet."
    )
    for fact in candidates:
        if not is_duplicate(fact, memory_md, threshold=0.85):
            append_to_memory_md(fact, source="session:"+session.id, ts=now())
```
Этот паттерн уже в Claude Code (auto-memory), Hermes (`~/.hermes/memories/MEMORY.md` cap 2200 chars), AutoMemoryTools в Spring AI 2026.

**Подвох:** агент склонен сохранять «болтовню». Жёсткий фильтр: ≥ 3 критериев из 5 (упомянуто 2+ раза, не вопрос, конкретика, источник, временная валидность).

**Источник:** [Claude Code Auto-Memory](https://www.mindstudio.ai/blog/what-is-claude-code-auto-memory), [Hermes Self-Improving AI](https://saulius.io/blog/hermes-agent-self-improving-ai-architecture), [Spring AI AutoMemoryTools](https://spring.io/blog/2026/04/07/spring-ai-agentic-patterns-6-memory-tools/), [memsearch by Zilliz](https://github.com/zilliztech/memsearch).

---

### 4. Memory Stress Test — golden questions + retrieval@k

**Что:** набор из 30–100 «золотых» вопросов с известными ответами. Прогоняй раз в неделю на новой памяти и считай:
- **Recall@k** — попал ли правильный факт в top-k результатов retrieval.
- **MRR** (Mean Reciprocal Rank) — насколько высоко.
- **Hit rate по эпохам** — какой % фактов 30/60/90-дневной давности агент ещё помнит.

**Когда применять:** прод. Без этого ты узнаёшь о деградации памяти от пользователя.

**Реализация:**
```yaml
# tests/memory-golden.yaml
- q: "В каком часовом поясе работает Дмитрий?"
  expected_facts: ["Москва", "MSK", "UTC+3"]
  must_appear_in_top_k: 5
  added_at: "2026-01-15"
- q: "Какой стек у проекта OpenClaw для Дмитрия?"
  expected_facts: ["VPS", "Mem0+Qdrant", "Cognee"]
  ...
```
Прогоняй через `mem0.search(query, k=5)` и сравнивай. Бенчмарки LongMemEval (5 способностей: extraction, multi-session, temporal, knowledge updates, abstention) и LoCoMo (300 turns × 35 sessions) — реальные академические аналоги.

**Подвох:** golden questions сами протухают. Раз в квартал — review.

**Источник:** [LongMemEval (arxiv)](https://arxiv.org/pdf/2410.10813), [LoCoMo benchmark](https://snap-research.github.io/locomo/), [Memanto: SOTA на обоих](https://arxiv.org/html/2604.22085), [Vectorize — Agent Memory Benchmark Manifesto](https://hindsight.vectorize.io/blog/2026/03/23/agent-memory-benchmark).

---

### 5. Forgetting Policy — что и когда удалять

**Что:** формальная политика забывания. Не всё хранить вечно — это и дорого, и шумит retrieval.

**Категории:**
| Слой | Время жизни | Пример |
|------|-------------|--------|
| Working memory (сессия) | до конца сессии | «сейчас обсуждаем ролик про X» |
| Short-Term (SML) | 7–30 дней | «вчера упомянул конкурента Y» |
| Long-Term (LML, semantic) | бессрочно с decay | «работает в часовом поясе MSK» |
| Procedural | до явного отзыва | «всегда публикуй с YT тегами от skill X» |
| Sensitive (PII) | retention window политики | «телефон знакомого» — 30 дней |

**Реализация — exp-time-decay:**
```
score = cosine_sim * exp(-lambda * days_since_last_seen)
лямбда: SML=0.05, LML=0.005, Procedural=0
```
Плюс LRU-eviction: при превышении лимита (например, 10K записей в Mem0) — удаляем низкий score первыми. Frameworks: MaRS (Memory-Aware Retention Schema), FadeMem (двухслойка LML/SML), ACT-R-inspired memory.

**Когда применять:** всегда после 1000+ записей в семантическом сторе.

**Подвох:** «никогда не удалять» персона/safety-правила. Тегируй их `pinned: true` — их не трогает никакой decay.

**Источник:** [Intelligent Forgetting (DEV)](https://dev.to/sudarshangouda/ai-agent-memory-part-2-the-case-for-intelligent-forgetting-4i48), [Human-Like Forgetting ACT-R](https://dl.acm.org/doi/10.1145/3765766.3765803), [Memanto: typed semantic memory](https://arxiv.org/html/2604.22085).

---

### 6. Memory Snapshot Diff — git-историзация памяти

**Что:** держи MEMORY.md (и memory/) в git-репо. Раз в день авто-коммит, раз в неделю — diff-отчёт «что добавилось/изменилось/удалилось».

**Когда применять:** прод-ассистенты. Даёт прозрачность — «откуда у бота это убеждение?».

**Реализация:**
```bash
# .openclaw/skills/memory-git-snapshot.md
0 3 * * * cd ~/.openclaw/agents/$AGENT && \
  git add -A && \
  git commit -m "snapshot $(date -I)" --allow-empty

# еженедельный отчёт
0 9 * * 1 git log --since="7 days ago" --stat MEMORY.md > weekly-diff.md && \
  llm summarize weekly-diff.md > weekly-narrative.md && \
  send_to_telegram weekly-narrative.md
```
Vertex AI Memory Bank пошёл дальше: каждый mutation создаёт immutable revision, есть API `RollbackMemory(revision_id)`. Это «git для памяти на API-уровне».

**Подвох:** не коммить секреты. Pre-commit hook на детекцию `.env`/токенов обязателен.

**Источник:** [Vertex AI Memory Revisions (Google)](https://docs.cloud.google.com/agent-builder/agent-engine/memory-bank/revisions), [Tim Kellogg — Memory Patterns](https://timkellogg.me/blog/2026/04/27/memory-patterns).

---

### 7. Hierarchical Memory — главное в MEMORY.md, детали в topic-files

**Что:** трёхуровневая иерархия:
- **L0** — `MEMORY.md` (~600 слов): persona, top-10 фактов, ссылки на L1.
- **L1** — `memory/semantic/topic-<X>.md` (3–5KB каждый): глубокие knowledge dumps по темам (контент, CRM, друзья, проекты).
- **L2** — векторный store (Mem0/Qdrant): сырые мелкие факты с embeddings.

При запросе агент сначала видит L0 (всегда в context), затем по индексу подгружает нужный L1, и только потом — L2 поиск. Экономия токенов, рост precision.

**Когда применять:** если MEMORY.md перевалил за 1500 слов — пора иерархизировать.

**Реализация под OpenClaw:**
```markdown
# MEMORY.md (L0)
## Index
- [Контент-стек] memory/semantic/topic-content.md
- [Друзья и контакты] memory/semantic/topic-people.md
- [OpenClaw setup] memory/semantic/topic-openclaw.md
...
## Top facts
- Дмитрий ведёт @ai_comandos (с янв 2024)
- Часовой пояс MSK
...
```
G-Memory (NeurIPS 2025) формализует это как трёхтировую графовую систему: insight, query, interaction.

**Подвох:** L1 файлы тоже могут разбухнуть. На каждом — лимит 5KB, иначе сплит.

**Источник:** [G-Memory: Hierarchical Memory for MAS (NeurIPS)](https://neurips.cc/virtual/2025/poster/116187), [Hierarchical Memory H-MEM (arxiv)](https://arxiv.org/abs/2507.22925), [VelvetShark OpenClaw masterclass](https://velvetshark.com/openclaw-memory-masterclass).

---

### 8. Multi-Vector Memory — несколько embeddings на один факт

**Что:** один факт хранится с 3 разными embeddings:
- **Semantic** — стандартный text-embedding (что сказано).
- **Temporal** — embedding с включённым timestamp («2 апреля 2026: …»).
- **Affective/style** — embedding с эмоц-маркером («с восторгом», «с усталостью»).

Запрос «что меня вчера расстраивало?» работает только если есть affective+temporal слои.

**Когда применять:** ассистенты, которые должны помнить эмоциональный контекст; контент-боты, которые ловят тон.

**Реализация:**
```python
# Qdrant с named vectors
collection: "memories"
vectors:
  semantic: { size: 1536 }
  temporal: { size: 768 }
  affective: { size: 384 }

# при записи
qdrant.upsert(
  id=fact_id,
  vectors={
    "semantic": embed(fact.text),
    "temporal": embed(f"{fact.timestamp}: {fact.text}"),
    "affective": embed(f"[{fact.emotion}] {fact.text}")
  }
)
```
MemoriesDB (arxiv 2511.06179) формально вводит «temporal-semantic-relational» вертексы.

**Подвох:** 3× места в Qdrant. Но и 3× качество retrieval по сложным запросам.

**Источник:** [MemoriesDB (arxiv)](https://arxiv.org/html/2511.06179), [Twelve Labs — multimodal embeddings](https://www.twelvelabs.io/blog/multimodal-embeddings), [Internal Emotion Memory](https://www.emergentmind.com/topics/internal-emotion-memory).

---

### 9. Time-aware Retrieval — temporal-aware search

**Что:** для запроса «что вчера обсуждали» обычный cosine не работает — он не различает «вчера» и «месяц назад». Нужен:
1. Темпоральный фильтр (`timestamp BETWEEN now-1d AND now`).
2. Decay-penalty на score: `final = sim * exp(-λ·Δdays)`.
3. Темпоральные графы: Graphiti/Zep — у каждого факта есть период валидности (`valid_from`, `valid_to`).

**Когда применять:** любой ассистент с длинной историей.

**Реализация под OpenClaw + Graphiti:**
```python
# Graphiti edge с временной валидностью
graphiti.add_episode(
  name="Дмитрий начал работать с Mem0",
  reference_time=datetime(2026, 4, 1),
  valid_from=datetime(2026, 4, 1),
  valid_to=None    # actively true
)

# Запрос «что нового было на прошлой неделе»
graphiti.search(
  query="что нового",
  time_range=(now-7d, now),
  weight_decay=0.1
)
```
Zep на DMR-benchmark обходит MemGPT (94.8 vs 93.4%).

**Подвох:** «вчера» в разных tz разное. Нормализуй timestamps в UTC + явный tz пользователя в MEMORY.md.

**Источник:** [Zep: Temporal KG for Agent Memory (arxiv)](https://arxiv.org/abs/2501.13956), [Graphiti by Zep (Github)](https://github.com/getzep/graphiti), [Graphiti / Neo4j blog](https://neo4j.com/blog/developer/graphiti-knowledge-graph-memory/).

---

### 10. Cross-reference Memory — граф связей без полноценного Cognee

**Что:** не нужно поднимать Cognee, чтобы получить «связи между фактами». Хватит лёгкого entity-extraction + JSON-индекса:

```json
// memory/entities.json
{
  "person:dmitriy": {
    "type": "person",
    "aliases": ["Дмитрий", "Попов", "владелец канала"],
    "facts": ["fact:tz_msk", "fact:channel_aicomandos"],
    "related": ["project:openclaw", "project:comandos"]
  },
  "project:openclaw": {
    "type": "project",
    "facts": ["fact:vps_setup", "fact:mem0_qdrant"],
    "related": ["person:peter_steinberger"]
  }
}
```
При retrieval: «расскажи про OpenClaw» → находишь project-узел → подтягиваешь все связанные facts + related entities.

**Когда применять:** до 500 сущностей — JSON-индекса хватит. Дальше — Cognee/Neo4j.

**Реализация:** ночной cron skill «extract entities» + LLM-canonicalization (Alice / Alice J. → один entity).

**Подвох:** entity resolution — самая сложная часть. Используй name-similarity ≥ 0.85 + LLM-judge для спорных.

**Источник:** [LINK-KG: Coreference-Resolved KGs](https://arxiv.org/html/2510.26486), [Graph-based Agent Memory taxonomy](https://arxiv.org/html/2602.05665v1), [Cognee Ontologies](https://www.cognee.ai/blog/deep-dives/grounding-ai-memory).

---

### 11. Privacy Partitions — публичная vs личная память по ролям

**Что:** один MEMORY.md = одна аудитория. Если у тебя контент-агент видит публику и личного ассистента видит ты — нельзя смешивать их памяти.

**Реализация под OpenClaw bindings:**
```
~/.openclaw/agents/
├── public-content/    # для канала, без PII
│   └── MEMORY.md     # стиль, темы, бренд
├── personal/         # только для Дмитрия
│   └── MEMORY.md    # друзья, расписание, финансы
```
Bindings разводят каналы: Telegram-канал → `public-content`, Telegram-DM Дмитрия → `personal`. Разные `agentDir` → нет утечки.

Mem0 / MemOS поддерживают metadata-теги `audience: public|private|team`, и retrieval фильтрует.

**Когда применять:** обязательно, как только у агента появилось 2+ канала.

**Подвох:** соблазн «просто шарить базу». Не делай — один лишний факт в публичный канал может стоить репутации.

**Источник:** [AI Agents and Memory: Privacy in MCP Era (New America)](https://www.newamerica.org/oti/briefs/ai-agents-and-memory/), [Memory Governance (Acuvity)](https://acuvity.ai/what-is-memory-governance-why-important-for-ai-security/), [Setting Permissions for AI Agents (Oso)](https://www.osohq.com/learn/ai-agent-permissions-delegated-access).

---

### 12. Memory Healing — точечный откат ошибочного факта

**Что:** агент узнал неверное («Анна — главред», но на самом деле Аня — редактор) и распространил в нескольких местах. Healing = точечный rollback ИМЕННО этого факта без потери остального.

**Реализация:**
1. Каждая mutation памяти = immutable revision (как в Vertex AI Memory Bank).
2. Каждый факт имеет `source_session_id` и `confidence`.
3. Команда `/memory heal "Анна — главред"`:
   - Найти все вхождения этого факта (через embedding).
   - Откатить к версии до их добавления.
   - Записать `correction:` запись с правильным ответом и `pinned: true`.

**Когда применять:** в любом ассистенте после первого «бот был уверен в неправде».

**Подвох:** просто удалить факт мало — модель уже могла его «впитать» в подсуммы. Поэтому добавляй явный «CORRECTED:» override, который перевешивает старое.

**Источник:** [Vertex AI Memory Revisions](https://docs.cloud.google.com/agent-builder/agent-engine/memory-bank/revisions), [LLM Memory Mechanisms (arxiv 2509.18868)](https://arxiv.org/pdf/2509.18868), [Tim Kellogg — Memory Patterns](https://timkellogg.me/blog/2026/04/27/memory-patterns).

---

### 13. Memory Consolidation — епизод → семантика на ночь

**Что:** ночной фоновый процесс (часто на маленькой быстрой модели — Haiku/Qwen) сканирует episodic за день, выделяет устойчивые факты, мержит в semantic store, разрешает противоречия.

**Реализация:**
```yaml
# .openclaw/skills/nightly-consolidation.md
trigger: cron "0 4 * * *"
model: haiku-4.5    # дешевая быстрая
flow:
  - read: memory/episodic/$(yesterday).md
  - extract_stable_facts: 
      criteria: "повторено 2+, не вопрос, конкретно, с источником"
  - for_each fact:
      - check_overlap_with: semantic_store
      - if duplicate: skip
      - if conflict: write conflict-report.md
      - else: upsert with confidence=0.7
  - archive episodic to memory/episodic/archive/
```
SimpleMem (arxiv 2601.02553) и LightMem (arxiv 2604.07798) формализуют это как «hierarchical compression» с semantic density gating.

**Когда применять:** если episodic за день > 50KB. Без консолидации stack растёт линейно.

**Подвох:** при компрессии теряются нюансы. Поэтому episodic держи 30 дней до архива, не удаляй сразу.

**Источник:** [SimpleMem: Efficient Lifelong Memory](https://arxiv.org/html/2601.02553), [LightMem (arxiv 2604.07798)](https://arxiv.org/html/2604.07798), [Hippocampo-neocortical compression model](https://www.biorxiv.org/content/10.1101/2024.11.04.621950v3).

---

## Часть 2. Advanced Retrieval — топ-7 паттернов

### 14. HyDE — Hypothetical Document Embeddings

**Что:** перед retrieval'ом просим LLM сгенерить «фейковый идеальный ответ» на запрос, embed-им именно его (а не сам запрос), и ищем в индексе. Часто запрос («Где обсуждали Mem0?») и документ («Mem0 это framework…») лежат в разных частях embedding-пространства; гипотетический ответ ближе к документу.

**Когда применять:** запросы короткие/абстрактные, а документы — длинные нарративы. Особенно — поиск по логам сессий и кодовой базе.

**Реализация:**
```python
def hyde_search(query, k=5):
    fake_answer = llm.generate(
        f"Напиши идеальный 1-абзацный ответ на: '{query}'. "
        "Не оговаривайся что не знаешь. Тон фактический."
    )
    embedding = embed(fake_answer)
    return vector_store.search(embedding, k=k)
```
Можно генерить 3–5 fake answers и комбинировать с RRF (см. ниже).

**Подвох:** на чисто фактических вопросах («какой у меня tz?») HyDE может уйти не туда. Используй adaptive: «сложный/абстрактный — HyDE, простой — обычный embed».

**Источник:** [HyDE original paper (Precise Zero-Shot Dense Retrieval)](https://arxiv.org/abs/2212.10496), [Haystack HyDE docs](https://docs.haystack.deepset.ai/docs/hypothetical-document-embeddings-hyde), [Zilliz HyDE explainer](https://zilliz.com/learn/improve-rag-and-information-retrieval-with-hyde-hypothetical-document-embeddings).

---

### 15. Step-back Prompting — расширение до общего вопроса

**Что:** «Что Дмитрий говорил про Qdrant в апреле?» → step-back: «Какие vector-store технологии Дмитрий использует?». Сначала ищем общее, потом фильтруем по конкретике.

**Когда применять:** многоступенчатые вопросы, где конкретный термин может не встречаться, а общая концепция — да.

**Реализация (LangChain):** есть готовый `StepBackRetriever` с шаблоном `step_back_template`. На OpenClaw — обычный pre-retrieval LLM-вызов:
```python
step_back_q = llm(f"Сформулируй более общий вопрос для: {q}")
results = retrieve(step_back_q) + retrieve(q)
return rerank(results)
```

**Подвох:** удваивает retrieval-стоимость. Применяй только когда первый поиск дал ≤ 3 результатов с низким score.

**Источник:** [LangChain — Query Transformations](https://blog.langchain.com/query-transformations/), [DeepMind Step-Back paper](https://arxiv.org/abs/2310.06117), [LangChain StepBackRetriever docs](https://python.langchain.com/v0.1/docs/use_cases/query_analysis/techniques/step_back/).

---

### 16. Multi-Query + Reciprocal Rank Fusion (RAG-Fusion)

**Что:** один вопрос → 4–5 переформулированных → каждый делает свой retrieval → объединяем через RRF: `score(d) = Σ 1/(k + rank_i(d))`.

**Метрики:** RAG-Fusion даёт +22% NDCG@5, +40% recall@10, +25% MRR vs наивный RAG.

**Когда применять:** всегда в проде, когда стоимость доп LLM-вызова окупается. Особенно для семантически неоднозначных запросов.

**Реализация:**
```python
def rag_fusion(query, k=10):
    queries = llm.generate_n(
        f"Переформулируй вопрос 4 разными способами: {query}", n=4
    ) + [query]
    all_results = [retriever.search(q, k=k) for q in queries]
    return reciprocal_rank_fusion(all_results, k_constant=60)

def reciprocal_rank_fusion(rankings, k_constant=60):
    scores = defaultdict(float)
    for ranking in rankings:
        for rank, doc in enumerate(ranking):
            scores[doc.id] += 1 / (k_constant + rank)
    return sorted(scores.items(), key=lambda x: -x[1])
```

**Подвох:** при `n=10` стоимость обращения растёт линейно. Сладкая точка — 4 query.

**Источник:** [RAG-Fusion paper (arxiv 2402.03367)](https://arxiv.org/abs/2402.03367), [Glaforge — RRF in Hybrid Search](https://glaforge.dev/posts/2026/02/10/advanced-rag-understanding-reciprocal-rank-fusion-in-hybrid-search/), [Raudaschl/rag-fusion (Github)](https://github.com/Raudaschl/rag-fusion).

---

### 17. Self-RAG — агент сам решает, нужен ли retrieval

**Что:** модель тренируется выпускать reflection-tokens: `[Retrieve]`, `[NoRetrieve]`, `[ContinueWithPrev]`, и затем `[Relevant]`/`[Irrelevant]` для каждого фрагмента. Не делает retrieval вслепую — только когда нужно.

**Когда применять:** длинные диалоги, где половина сообщений «спасибо/как дела» — там retrieval бесполезен и дорог.

**Реализация без файнтюна (через prompt + Haiku-judge):**
```python
def self_rag(query, history):
    decision = haiku.generate(
        f"Нужен ли retrieval для ответа на: '{query}' "
        f"при истории: {history[-3:]}? "
        "Ответь YES/NO/USE_PREVIOUS одним словом."
    )
    if decision == "YES":
        ctx = retrieve(query)
        return main_model.generate(query, ctx)
    elif decision == "USE_PREVIOUS":
        return main_model.generate(query, last_ctx)
    else:
        return main_model.generate(query)
```

**Подвох:** judge-модель может врать в обе стороны. Метрика: false-skip rate (когда retrieval нужен, а агент его не сделал) — должен быть < 5%.

**Источник:** [Self-RAG paper](https://arxiv.org/abs/2310.11511), [Analytics Vidhya — Self-RAG](https://www.analyticsvidhya.com/blog/2025/01/self-rag/), [Adaptive RAG (Sumit's Diary)](https://blog.reachsumit.com/posts/2025/10/learning-to-retrieve/).

---

### 18. GraphRAG — поиск через граф знаний

**Что:** Microsoft GraphRAG строит из корпуса knowledge-граф + community summaries, и при запросе выполняет: retrieve по сообществам → multi-hop traversal → собрать ответ. Точность multi-hop вопросов в 3.4× выше vector-RAG.

**Когда применять:** если у тебя большая base знаний (50+ MB markdown, проектная документация, переписки) с многосвязными сущностями. Пример Дмитрия — все 20 .md блоков OpenClaw + переписка по проектам.

**Реализация:** GraphRAG (Microsoft) или LazyGraphRAG (тот же стек, но 0.1% стоимости индексации). Под OpenClaw — Cognee/Graphiti (уже в blocк 20).

**Подвох:** stockup-индексации дорог; Lazy-вариант это решает.

**Источник:** [Microsoft GraphRAG](https://microsoft.github.io/graphrag/), [GraphRAG paper / LazyGraphRAG](https://www.microsoft.com/en-us/research/project/graphrag/), [Neo4j — What is GraphRAG](https://neo4j.com/blog/genai/what-is-graphrag/).

---

### 19. ColBERT Late-Interaction — для high-precision retrieval

**Что:** обычный embedding сжимает документ до одного вектора → теряет тонкие совпадения. ColBERT хранит embedding каждого токена и при поиске считает `MaxSim` между каждым токеном запроса и документа. Точность как у cross-encoder, скорость как у bi-encoder.

**Когда применять:** legal/financial/code retrieval, где «почти то же самое» != «то же самое». Для личного ассистента — overkill, для контракт-парсинга — must.

**Реализация:** `colbert-ai` или `RAGatouille` (Python). Под Qdrant — multi-vector mode + sum-of-max scorer.

**Подвох:** в 30–50× больше места под индекс. ColBERTv2 сжимает в 6–10× лучше.

**Источник:** [ColBERT paper (arxiv 2004.12832)](https://arxiv.org/abs/2004.12832), [ColBERTv2 paper](https://arxiv.org/abs/2112.01488), [Weaviate — Late Interaction overview](https://weaviate.io/blog/late-interaction-overview), [Stanford ColBERT (Github)](https://github.com/stanford-futuredata/ColBERT).

---

### 20. RAFT — Retrieval-Augmented Fine-Tuning

**Что:** тренируем модель отличать «полезный документ» от «дистрактора» в контексте. Получаем модель, которая работает в конкретном домене (твой стек, твои термины) даже с шумным retrieval'ом.

**Когда применять:** через 6+ месяцев работы в проде, когда у тебя есть размеченные пары (запрос → правильный документ). Ранее этой стадии — обычный RAG.

**Реализация:** [RAFT lib (Lumpenspace)](https://github.com/lumpenspace/raft) на 7B-моделях. Для Дмитрия — overkill сейчас, но через год — крутая опция кастомизации Mistral/Qwen под его язык/стек.

**Источник:** [RAFT paper (arxiv 2403.10131)](https://arxiv.org/abs/2403.10131), [Berkeley Gorilla blog](https://gorilla.cs.berkeley.edu/blogs/9_raft.html), [Meta — RAFT for Llama](https://ai.meta.com/blog/raft-llama-retrieval-augmented-generation-supervised-fine-tuning-microsoft/).

---

## Часть 3. Multi-agent — топ-8 паттернов

### 21. Orchestrator-Worker (Anthropic Lead-Subagent)

**Что:** lead-агент анализирует запрос, разбивает на подзадачи, спавнит 3–5 sub-агентов параллельно, каждый со своим контекстом, потом lead собирает финальный ответ. Anthropic с этим паттерном выиграл +90.2% качества над single-Opus.

**Когда применять:** ресёрч, многоисточниковый сбор данных, сравнения. Не применять для коротких задач (<10 LLM-вызовов).

**Реализация под OpenClaw `sessions_spawn`:**
```yaml
# .openclaw/agents/research-lead/SOUL.md
ROLE: orchestrator
ON_USER_QUERY:
  1. Decompose query into 3-5 parallel subtasks (with explicit boundaries)
  2. For each subtask: sessions_spawn → research-worker
  3. Wait for all completions (timeout 60s)
  4. Synthesize, cite sources, return
EFFORT_SCALING:
  simple_fact: 1 worker, 3-10 tool calls
  comparison: 2-4 workers, 10-15 tool calls each
  deep_research: 5-10 workers
```
Worker-prompt должен иметь: clear objective + output format + tool guidance + boundaries (не дублировать чужой scope).

**Метрики из Anthropic:** token usage = 80% of variance. Multi-agent тратит 15× токенов vs single — окупается только на high-value задачах.

**Подвох:** synchronous bottleneck (lead ждёт всех). Решение — partial-results streaming.

**Источник:** [Anthropic — Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system), [When to use multi-agent (Claude blog)](https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them), [Constellation — must-read for CIOs](https://www.constellationr.com/blog-news/insights/anthropics-multi-agent-system-overview-must-read-cios).

---

### 22. Pipeline (Sequential Assembly Line)

**Что:** A → B → C → D, каждый строго следующий, output одного = input следующего. Контракты I/O жёсткие.

**Когда применять:** контент-team (research → write → edit → publish), CRM-flow (score → enrich → outreach), deploy-pipeline. Когда ПОРЯДОК важен и каждый шаг — детерминирован.

**Реализация под OpenClaw flows:**
```yaml
# CrewAI Flows / OpenClaw bindings sequence
flow: content-pipeline
steps:
  - agent: researcher    # выход: research.md
  - agent: writer        # вход: research.md, выход: draft.md
  - agent: editor        # вход: draft.md, выход: final.md
  - agent: publisher     # вход: final.md, действие: publish to YT/VK/Дзен
```

**Подвох:** scalability ограничена слабейшим звеном (`max(stage_latencies)`); fault-tolerance низкая (failed stage = всё стоит). Решение: на каждой стадии — checkpoint (LangGraph-style).

**Источник:** [Agent Orchestration: Pipeline vs Mesh vs Hierarchical (DEV)](https://dev.to/jose_gurusup_dev/agent-orchestration-patterns-swarm-vs-mesh-vs-hierarchical-vs-pipeline-b40), [Microsoft Azure — AI Agent Design Patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns), [CrewAI Flows production guide](https://www.jahanzaib.ai/blog/crewai-flows-production-multi-agent-guide).

---

### 23. Mesh / Peer-to-Peer

**Что:** агенты общаются друг с другом напрямую без центрального оркестратора. У каждого свой набор пиров, явные каналы.

**Когда применять:** collaborative reasoning, code review loops, итеративная доработка артефакта. Не применять более чем для 4–5 агентов (N² сложность связей).

**Реализация под OpenClaw:**
```
agent-A.bindings → agent-B (через A2A protocol, см. ниже #36)
agent-B.bindings → agent-A, agent-C
```
Под капотом — обмен через общий store или прямые webhooks.

**Подвох:** debug-кошмар. Лимитируй до 3–4 агентов и логируй каждое сообщение.

**Источник:** [Multi-Agent Architecture Patterns (Tetrate)](https://tetrate.io/learn/ai/multi-agent-systems), [DEV — Mesh vs Hierarchical](https://dev.to/jose_gurusup_dev/agent-orchestration-patterns-swarm-vs-mesh-vs-hierarchical-vs-pipeline-b40), [Agentic Mesh Patterns (DEV)](https://dev.to/vishalmysore/understanding-agentic-mesh-patterns-and-multi-language-implementation-14a6).

---

### 24. Council / Voting

**Что:** N (нечётное!) агентов независимо решают задачу, координатор считает голоса. Бывает majority/weighted/Borda. Voting protocols дают +13.2% на reasoning задачах.

**Когда применять:** критичные решения (отправлять ли клиенту, публиковать ли пост, тратить ли бюджет на ads). Когда стоимость ошибки выше стоимости 3-кратной инференции.

**Реализация:**
```yaml
council_publish_decision:
  voters:
    - agent: editor (weight: 2)    # эксперт по контенту
    - agent: brand-guardian (weight: 1)
    - agent: legal-checker (weight: 1)
  question: "Публиковать пост X в @ai_comandos?"
  threshold: weighted_majority
  on_tie: escalate_to_human
```

**Подвох:** «adversarial influence» — один уверенно неправильный агент может завалить группу (–10..40% accuracy в исследованиях). Контрмера: silent voting (агенты не видят чужие ответы) + diverse models (Opus, Sonnet, Qwen — не одна семья).

**Источник:** [Voting or Consensus? (ACL 2025)](https://aclanthology.org/2025.findings-acl.606/), [Patterns for Democratic Multi-Agent AI](https://medium.com/@edoardo.schepis/patterns-for-democratic-multi-agent-ai-voting-based-council-part-1-9a9164a173ff), [Council Mode: Mitigating Hallucination (arxiv)](https://arxiv.org/html/2604.02923v2), [Adversarial influence in MAD (Nature)](https://www.nature.com/articles/s41598-026-42705-7).

---

### 25. Adversarial Debate / Critic

**Что:** один агент-actor предлагает решение, второй агент-critic ищет в нём дыры. Итерация до сходимости. Reflexion (91% pass@1 на HumanEval, выше GPT-4) — пример.

**Когда применять:** написание кода, юр-документы, любой текст где «вторая пара глаз» полезна.

**Реализация:**
```yaml
debate_loop:
  max_rounds: 3
  actor_prompt: "Реши задачу X."
  critic_prompt: "Найди ≥ 2 проблемы в решении actor. Если идеально — скажи DONE."
  exit_when: critic.says("DONE") OR rounds >= 3
```
Под OpenClaw — два sessions_spawn, обмен через файл `debate-log.md` или прямой messaging.

**Подвох:** infinite-debate-loop, когда оба агента упрямые. Hard cap на rounds.

**Источник:** [Reflexion paper (arxiv 2303.11366)](https://arxiv.org/abs/2303.11366), [LangChain Reflection Agents](https://blog.langchain.com/reflection-agents/), [DeepLearning.AI — Reflection pattern](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-2-reflection/), [ACC-Debate (Actor-Critic)](https://arxiv.org/html/2411.00053v1).

---

### 26. Reflection — агент сам себя проверяет

**Что:** generate → self-critique → refine. В отличие от debate, это один агент в трёх режимах. Отличие Reflection от Reflexion: первый — внутри одного диалога, второй — учится через эпизоды.

**Когда применять:** длинные ответы, code-gen. Лёгкая версия debate.

**Реализация:**
```python
def reflect(task, max_iters=3):
    answer = llm.generate(task)
    for i in range(max_iters):
        critique = llm.generate(f"Найди слабые места в: {answer}")
        if "ALL_GOOD" in critique:
            break
        answer = llm.generate(f"Перепиши учитывая: {critique}\nИсходник: {answer}")
    return answer
```

**Подвох:** не помогает на задачах за пределами знаний модели — она не видит того, чего не знает.

**Источник:** [Reflexion paper (arxiv 2303.11366)](https://arxiv.org/abs/2303.11366), [Agentic Design Patterns — Reflection (Mathews-Tom)](https://github.com/Mathews-Tom/Agentic-Design-Patterns), [Building the Reflector (Medium 2026)](https://medium.com/@Micheal-Lanham/building-the-reflector-how-self-correcting-agents-actually-compute-what-went-wrong-4d6e239f6723).

---

### 27. Handoff Pattern (OpenAI Swarm / Agents SDK)

**Что:** в отличие от tool-delegation («помоги мне с X, но я закончу разговор»), handoff = «передаю тебе разговор полностью». Текущий агент уходит, новый берёт всю историю.

**Когда применять:** triage-системы (входящий запрос → распознать тип → передать спец-агенту); CRM (lead → qualifier → если квалиф → outreach-agent забирает).

**Реализация под OpenClaw:**
```yaml
# triage-agent.bindings
on_intent("billing"): handoff_to: billing-agent
on_intent("technical"): handoff_to: tech-agent
on_intent("escalation"): handoff_to: human (Telegram DM Дмитрия)
```

**Подвох:** «hot-potato handoff» — агенты перебрасывают друг другу пользователя. Контрмера: max-handoffs=2 на сессию.

**Источник:** [OpenAI Swarm (Github)](https://github.com/openai/swarm), [OpenAI Cookbook — Orchestrating Agents](https://cookbook.openai.com/examples/orchestrating_agents), [AutoGen Handoffs docs](https://microsoft.github.io/autogen/stable//user-guide/core-user-guide/design-patterns/handoffs.html).

---

### 28. Agents-as-Tools (Tool Delegation)

**Что:** sub-агент НЕ забирает разговор, а вызывается как обычный tool. Главный агент остаётся, получает structured-output sub-агента и продолжает.

**Когда применять:** когда главный агент должен СВЕСТИ несколько sub-результатов. Контент-агент вызывает researcher-tool, fact-checker-tool, brand-tool — но финал пишет сам.

**Реализация:**
```python
@tool
def deep_research(query: str) -> str:
    """Глубокий research через sub-agent."""
    return openclaw.spawn_session("researcher", query).wait()

# главный агент использует это как обычный tool
```

**Подвох:** vs handoff — путают часто. Handoff = «уйди и не возвращайся», agent-as-tool = «помоги и верни данные мне».

**Источник:** [Strands Agents — Agents as Tools](https://strandsagents.com/docs/user-guide/concepts/multi-agent/agents-as-tools/), [AWS — Agents as Tools pattern](https://dev.to/aws/build-multi-agent-systems-using-the-agents-as-tools-pattern-jce), [CodeSignal — Orchestrating Agents as Tools](https://codesignal.com/learn/courses/mastering-agentic-patterns-with-claude/lessons/orchestrating-agents-as-tools-1).

---

## Часть 4. Координация и надёжность — топ-6

### 29. Blackboard — общая память для команды

**Что:** агенты не общаются напрямую, а пишут/читают общую «доску» (shared state). Контроллер выбирает, кому писать следующим, на основе состояния доски.

**Когда применять:** когда задача — «кто-то когда-то заметит и сделает». Например, мониторинг: один агент пишет «новый PR появился», другой видит и проверяет, третий пишет changelog.

**Реализация под OpenClaw:** shared SQLite/Redis в `~/.openclaw/shared/blackboard.db`. Каждое действие — `(agent_id, ts, type, payload)`. Агенты подписаны на изменения через polling/webhook.

**Подвох:** race conditions. Используй optimistic locking (`version` поле + CAS).

**Источник:** [LLM Multi-Agent Blackboard System (arxiv 2510.01285)](https://arxiv.org/pdf/2510.01285), [Building MAS with MCPs and Blackboard (Medium)](https://medium.com/@dp2580/building-intelligent-multi-agent-systems-with-mcps-and-the-blackboard-pattern-to-build-systems-a454705d5672), [Blackboard Architecture in Agentic AI (DataFlair)](https://data-flair.training/blogs/blackboard-architecture-in-agentic-ai/).

---

### 30. Event Sourcing — журнал каждого действия

**Что:** не сохраняй конечное состояние — сохраняй полный лог событий. Состояние = свёртка всех событий до момента T. Можно перевоспроизвести любой момент.

**Когда применять:** прод-агенты, где нужна полная аудит-история. Регулируемые домены (CRM, финансы), компании где «кто решил это сделать?» — частый вопрос.

**Реализация:** Postgres-таблица `events(agent_id, ts, type, payload, idempotency_key)`. Запрос «что бот сказал клиенту X 3 дня назад?» — `WHERE customer=X AND ts BETWEEN ...`.

**Отличие от audit-log:** audit фиксирует «что произошло», event-sourcing восстанавливает состояние. Если бот сделал ошибку — replay лога с исправленной логикой.

**Подвох:** объём растёт; нужно snapshotting раз в N событий.

**Источник:** [Event Sourcing pattern (Azure)](https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing), [Kurrent — Event Sourcing vs Audit Log](https://www.kurrent.io/blog/event-sourcing-audit), [Confluent — Event Sourcing Intro](https://www.confluent.io/learn/event-sourcing/).

---

### 31. Idempotency Keys — безопасный retry

**Что:** на каждый stateful tool-call агент генерит уникальный детерминированный `idempotency-key` (например, `hash(agent_id + task_id + step_n)`). Tool сохраняет результат под ключом; повторный вызов с тем же ключом возвращает кешированный ответ.

**Когда применять:** ВСЕГДА в проде, особенно: оплаты, отправка email/Telegram, посты в соцсети, создание задач в CRM.

**Реализация:**
```python
def send_email_idempotent(to, subject, body, idem_key):
    if cache.get(idem_key):
        return cache.get(idem_key)    # уже отправлено
    result = email_provider.send(to, subject, body, 
                                  Idempotency_Key=idem_key)
    cache.set(idem_key, result, ttl=24h)
    return result
```
AgentMail и Stripe нативно поддерживают `Idempotency-Key` header.

**Подвох:** ключ должен быть детерминированным (одинаковый при retry того же действия) и уникальным (не пересекаться между разными действиями). `random.uuid()` ломает идемпотентность.

**Источник:** [Idempotent AI Agents (BuildMVPFast)](https://www.buildmvpfast.com/blog/idempotent-ai-agent-retry-safe-patterns-production-workflow-2026), [AWS — Making retries safe with idempotent APIs](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/), [Adaline Labs — Reliable Tool-Using Agents](https://labs.adaline.ai/p/reliable-tool-using-ai-agents-production), [Idempotency in AI Tools (DZone)](https://dzone.com/articles/idempotency-in-ai-tools-most-expensive-mistake).

---

### 32. Saga Pattern — откат сложной транзакции

**Что:** длинная цепочка `A → B → C → D`. Если D упал, нужно откатить C, B, A через compensating actions. Не просто «откат», а смысловые «обратные» действия (если post опубликован — `delete_post`, если деньги списаны — `refund`).

**Когда применять:** многошаговые pipeline, где каждый шаг имеет внешний side effect.

**Реализация (Orchestration variant):**
```yaml
saga: publish-content
steps:
  - action: render_video        # compensate: delete_local_file
  - action: upload_youtube      # compensate: yt.delete(id)
  - action: post_telegram       # compensate: tg.delete(msg_id)
  - action: notify_email        # compensate: send_correction_email
on_fail_at_step_n:
  for i in range(n-1, -1, -1): run compensation_i
```

**Подвох:** compensations должны быть idempotent (см. #31). Иногда настоящий откат невозможен (email уже прочитан) — тогда compensation = «отправить correction».

**Источник:** [Saga pattern (microservices.io)](https://microservices.io/patterns/data/saga.html), [Azure — Saga Design Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/saga), [Compensation Transaction Patterns (Orkes)](https://orkes.io/blog/compensation-transaction-patterns/), [Temporal — Mastering Saga Patterns](https://temporal.io/blog/mastering-saga-patterns-for-distributed-transactions-in-microservices).

---

### 33. Circuit Breaker — отключение упавшего агента

**Что:** если агент/провайдер упал N раз за окно T — закрываем circuit, на M минут не отправляем туда запросы, переходим на fallback. Через M минут — half-open: пробуем 1 запрос, если ок — open снова.

**Когда применять:** ВСЕГДА в проде. LLM-провайдеры падают 1–5% времени; circuit breaker отличает «случайный сбой» от «провайдер лежит».

**Реализация:**
```yaml
circuit_breaker:
  trigger: 40% failure rate in 60s window
  open_duration: 5min
  fallback: secondary_provider (например, Anthropic → OpenAI)
  half_open_test: 1 request after 5min
```
Salesforce Agentforce: при ≥40% failure OpenAI-traffic в 60-секундном окне → весь трафик на Azure-mirror. Portkey/Maxim/n1n.ai — готовые сервисы.

**Подвох:** не путай circuit с retry. Retry — индивидуальные сбои. Circuit — системные.

**Источник:** [Portkey — Retries, Fallbacks, Circuit Breakers in LLM apps](https://portkey.ai/blog/retries-fallbacks-and-circuit-breakers-in-llm-apps/), [Maxim — Production Guide](https://www.getmaxim.ai/articles/retries-fallbacks-and-circuit-breakers-in-llm-apps-a-production-guide/), [n1n.ai — Circuit Breakers for LLM APIs](https://explore.n1n.ai/blog/circuit-breakers-llm-api-sre-reliability-patterns-2026-02-15), [Brandon Lincoln Hendricks — Circuit Breaker Patterns](https://brandonlincolnhendricks.com/research/circuit-breaker-patterns-ai-agent-reliability).

---

### 34. Backpressure — main не ждёт research больше 60 сек

**Что:** при fan-out (lead спавнит 5 worker'ов) кто-то долго отвечает. Backpressure = bounded queues + timeouts + graceful degradation: если worker не ответил за T — закрываем его, синтезируем ответ из тех, кто успел.

**Когда применять:** Anthropic-style multi-agent в продакшене.

**Реализация (Python asyncio):**
```python
async def fan_out_with_backpressure(workers, timeout=60):
    sem = asyncio.Semaphore(5)  # max parallel
    async def run(w):
        async with sem:
            try:
                return await asyncio.wait_for(w.run(), timeout)
            except asyncio.TimeoutError:
                return PartialResult(worker=w, status="timeout")
    return await asyncio.gather(*[run(w) for w in workers])
```

**Подвох:** не нагружай fallback partial-result слишком оптимистично. Помечай явно `[partial]` для пользователя.

**Источник:** [Vercel AI SDK — Backpressure](https://ai-sdk.dev/docs/advanced/backpressure), [Back-Pressure Agent (aipatternbook)](https://aipatternbook.com/back-pressure), [Managing Backpressure in Async AI Services](https://dasroot.net/posts/2026/02/managing-backpressure-async-ai-services/).

---

## Часть 5. Эвалюация и анти-паттерны

### 35. Trace-level vs Outcome-level Evaluation

**Что:** две разных метрики:
- **Trace** — оценить КАЖДОЕ действие агента (правильно ли выбрал tool, правильно ли распарсил, правильный ли prompt).
- **Outcome** — только финальный результат (доволен ли пользователь, опубликовался ли пост).

**Когда применять:**
- Trace — при поиске багов, регрессии, тонкой оптимизации.
- Outcome — для бизнес-KPI, A/B-тестов.
- **Counterfactual** — «что было бы если бы lead НЕ делегировал?». Прогон того же запроса в режиме single-agent — сравни результат и cost.

**Реализация:** OpenAI Evals API, LangSmith traces, Langfuse. Всё пишут TS-логи + scoring rubric.

**Anthropic подсказывает:**
- 20 representative test queries — уже даёт сильный сигнал.
- LLM-as-judge с rubric (factual accuracy, citation, completeness) — масштабируемо.
- Human eval — для edge-cases.
- End-state eval лучше step-by-step — агенты находят альтернативные правильные пути.

**Подвох:** trace-eval перфекционизм может тормозить итерацию. Outcome-eval может скрыть «бот ходил кривым путём, но результат вышел». Используй ОБА.

**Источник:** [OpenAI — Evaluate agent workflows](https://developers.openai.com/api/docs/guides/agent-evals), [Anthropic Multi-Agent System (eval section)](https://www.anthropic.com/engineering/multi-agent-research-system), [Counterfactual Evaluation (Eugene Yan)](https://eugeneyan.com/writing/counterfactual-evaluation/), [Agentic Evaluation Framework](https://www.elixirclaw.ai/blog/agentic-evaluation).

---

### 36. Cost-Quality Pareto Frontier — какие модели для каких ролей

**Что:** не используй frontier-модель для всего. Optimal — двухмодельная композиция:
- **Frontier (Opus 4.7, GPT-5)** — для творчества, judgment, реддиум, outreach-копирайтинг.
- **Mid (Sonnet 4.6, MiMo V2 Pro, Qwen 3.6 Plus)** — для retrieval, rerank, summarization, basic reasoning.
- **Cheap (Haiku 4.5, GPT-4o-mini)** — для классификации, lead-scoring, parsing.

Real numbers: knee point of Pareto — теряешь ≤ 5% качества, экономишь 10×.

**Готовая раскладка для команды Дмитрия:**
| Роль | Модель | Почему |
|------|--------|--------|
| Lead orchestrator | Opus 4.7 | Делегирование = creative |
| Researcher worker | Sonnet 4.6 | Объёмные tool-calls |
| Writer | Opus 4.7 | Качество текста — главное |
| Editor / Critic | Sonnet 4.6 | Проверка по rubric |
| Lead-scorer (CRM) | Haiku 4.5 | Классификация |
| Memory linter | Haiku 4.5 | Скучная регулярная работа |
| Memory consolidator | Haiku 4.5 (ночной) | Объём + дешевизна |

**Источник:** [Cobus Greyling — Pareto Frontier for AI Agents](https://cobusgreyling.medium.com/the-pareto-frontier-for-ai-agents-fa477eaaac6e), [MindStudio — Token Cost Optimization](https://www.mindstudio.ai/blog/ai-agent-token-cost-optimization-multi-model-routing), [DigitalApplied — AI Model Efficient Frontier Q2 2026](https://www.digitalapplied.com/blog/ai-model-performance-vs-price-efficient-frontier-q2), [DataRobot — Syftr Pareto-optimal workflows](https://www.datarobot.com/blog/pareto-optimized-ai-workflows-syftr/).

---

## Когда НЕ нужны мульти-агенты — anti-patterns

### Anti-pattern A: Multi-Agent Overkill

**Сигналы:**
- Типичный запрос проходит ≥4 хэндофа, хотя 1–2 хватило бы.
- Один и тот же кейс идёт разными цепочками между прогонами.
- Добавление нового агента **ухудшает** P95-latency и success-rate.
- Команда не может ответить «кто отвечает за финальный output».

**Цифры:** документ-анализ-pipeline на 4 агентах = 35 000 токенов vs 10 000 у single (3.5×). MetaGPT — 72% token duplication, CAMEL — 86%, AgentVerse — 53%.

**Правило большого пальца:** 3–5 хорошо определённых агентов > 10 размытых.

### Anti-pattern B: Слишком глубокая иерархия (>3 уровня)

Каждый уровень удваивает latency и удлиняет цепочку ошибок. 3 уровня — потолок: orchestrator → 5 specialists → каждый со своими tool-agents. Дальше — perf collapse.

### Anti-pattern C: Циркулярные зависимости

A зовёт B, B зовёт C, C зовёт A. Лечится hard-cap на handoff depth + явный DAG в config-time.

### Anti-pattern D: Агент без spending cap

Любой агент в проде должен иметь:
- max-tokens-per-session
- max-cost-per-day (через провайдера или middleware)
- max-tool-calls-per-task

Без них — один баг = $1000 в OpenAI за ночь.

**Источник:** [Multi-Agent Overkill (Agent Patterns)](https://www.agentpatterns.tech/en/anti-patterns/multi-agent-overkill), [The Multi-Agent Trap (Towards Data Science)](https://towardsdatascience.com/the-multi-agent-trap/), [Why MAS Fail in Practice (Medium)](https://raghunitb.medium.com/why-multi-agent-systems-often-fail-in-practice-and-what-to-do-instead-890729ec4a03), [Galileo — Coordination Strategies](https://galileo.ai/blog/multi-agent-coordination-strategies).

---

## Готовые шаблоны команд под use cases Дмитрия

### Шаблон 1. Контент-команда (4 роли)

**Цель:** канал @ai_comandos, 3+ постов/день.

```yaml
# .openclaw/teams/content/
agents:
  - id: researcher
    model: sonnet-4.6
    role: "Изучить тему через WebSearch+WebFetch (5+ источников), 
          собрать факты + ссылки в research-{topic}.md"
    tools: [web_search, web_fetch]
    spending_cap: 0.3 USD/task
    
  - id: writer  
    model: opus-4.7
    role: "Из research.md написать пост в стиле канала. 
          Stylе/тон из MEMORY.md. Длина 600-800 слов."
    tools: [read_file, write_file]
    
  - id: editor
    model: sonnet-4.6
    role: "Прогнать draft через 5-checks: factual / brand-voice / 
          грамматика / SEO / hook первой строки. Reflexion-цикл max 2."
    tools: [read_file, write_file]
    
  - id: publisher
    model: haiku-4.5
    role: "Опубликовать через video-seo-publisher skill. 
          Idempotency-key = hash(post_id+platform)."
    tools: [yt_publish, vk_publish, dzen_publish, tg_publish]

flow: pipeline
fallback_on_editor_reject: human_review_in_telegram
```

**Pattern-stack:** Pipeline (#22) + Reflection (#26) + Idempotency (#31) + Cost-Quality routing (#36).

---

### Шаблон 2. CRM-команда (4 роли)

**Цель:** обрабатывать входящие лиды (форма / email).

```yaml
agents:
  - id: lead-triage  
    model: haiku-4.5
    role: "Определить: spam / cold / warm / hot. Если spam — drop. 
          Иначе → enricher."
    
  - id: enricher
    model: haiku-4.5
    role: "Обогатить через Clearbit/LinkedIn API. 
          Записать в CRM."
    tools: [clearbit, linkedin_lookup, crm_write]
    spending_cap: 0.05 USD/lead
    
  - id: qualifier
    model: sonnet-4.6
    role: "Применить 3 scoring-rubrics параллельно (BANT, MEDDIC, custom). 
          Вывод: score + reasoning."
    output_format: structured_json
    
  - id: outreach-author
    model: opus-4.7   # frontier — quality reply rate
    role: "Написать персонализированный 3-step sequence. 
          Учесть данные enricher и language preference."
    
flow: handoff_chain (triage → enricher → qualifier → outreach)
on_low_score: handoff_to: nurture-sequence (long-term newsletter)
```

**Pattern-stack:** Handoff (#27) + Council для qualifier (#24, 3 rubrics голосуют) + Cost-Quality (#36).

---

### Шаблон 3. Personal Assistant (3 роли)

**Цель:** триаж сообщений (Telegram, email), draft ответов, человек подтверждает.

```yaml
agents:
  - id: triage  
    model: haiku-4.5
    role: "Каждое входящее: классифицировать (urgent / routine / spam / scheduled). 
          Spam — silent drop. Routine — предложить шаблон. 
          Urgent — пинг."
    memory_partition: personal
    
  - id: drafter
    model: sonnet-4.6
    role: "Из контекста (треды, MEMORY.md) набросать 2 варианта ответа. 
          Stylе и tone — из user-profile."
    memory_access: [MEMORY.md, memory/people/, last_30_threads]
    
  - id: confirmer  
    model: ----
    role: "Не LLM. Это человек (Дмитрий) — кнопка [✓ Send / ✏️ Edit / ✗ Skip] 
          в Telegram."
    
flow: triage → drafter → confirmer (human-in-the-loop)
```

**Pattern-stack:** Privacy partitions (#11) + Memory healing для исправлений (#12) + Self-RAG (#17, нужен ли retrieval?) + всегда human-in-loop на irreversible.

---

## Гибридная память Mem0 + Cognee + MEMORY.md — кто источник истины

При конфликте источник истины определяется приоритетом:

```
1. MEMORY.md / AGENTS.md  → правила и persona (HIGHEST, immutable in session)
2. Mem0 / Qdrant          → semantic facts с confidence + last_seen
3. Graphiti / Cognee KG   → temporal facts с valid_from/valid_to
4. Episodic store         → сырые события (LOWEST, raw data)
```

**Алгоритм при конфликте «сегодня сказал X, а в Mem0 было Y»:**
1. Если факт в MEMORY.md `pinned: true` — игнорируй новое.
2. Если Graphiti говорит «факт Y был валиден до вчера» — обнови валидность, новый Y_today становится current.
3. Если оба активны — escalate to user: «У меня два противоречия: X (вчера) vs Y (сейчас). Какое верно?»
4. После ответа → memory healing (#12) на проигравший факт.

---

## Тренды апреля 2026

- **A2A protocol v1.2 в проде у 150+ компаний.** Microsoft, AWS, Salesforce, SAP, ServiceNow гоняют на нём prod-трафик. Linux Foundation Agentic AI Foundation governance. Signed agent cards (cryptographic verification of agent identity).
- **CrewAI Flows на 12M executions/day.** Использует 60% Fortune 500. Появилась интеграция с NVIDIA NemoClaw для self-evolving agents.
- **LangGraph time-travel debugging** в стандарте — checkpoint-based replay любого агента.
- **Memanto — SOTA на LongMemEval (89.8%) + LoCoMo (87.1%).** Typed semantic memory + information-theoretic retrieval.
- **LazyGraphRAG** — 0.1% стоимости индексирования полного GraphRAG. Microsoft Discovery платформа в Azure.
- **Mem0 v1.0.0 API** — первый mainstream-фреймворк с явной поддержкой procedural memory (третий слой триады).
- **G-Memory (NeurIPS)** — иерархическая графовая память для multi-agent систем (insight / query / interaction subgraphs).

**Источники:** [A2A Protocol v1.2 status](https://cloud.google.com/blog/products/ai-machine-learning/agent2agent-protocol-is-getting-an-upgrade), [CrewAI 2B executions](https://blog.crewai.com/lessons-from-2-billion-agentic-workflows/), [LangGraph 2026 features](https://medium.com/@dewasheesh.rana/langgraph-explained-2026-edition-ea8f725abff3), [Memanto SOTA](https://arxiv.org/html/2604.22085), [LazyGraphRAG](https://www.microsoft.com/en-us/research/project/graphrag/), [Mem0 v1.0.0 procedural memory](https://mem0.ai/blog/state-of-ai-agent-memory-2026), [G-Memory NeurIPS](https://neurips.cc/virtual/2025/poster/116187).

---

## Источники (полный список)

### Память
- [Position: Episodic Memory is the Missing Piece — arxiv 2502.06975](https://arxiv.org/pdf/2502.06975)
- [State of AI Agent Memory 2026 — Mem0](https://mem0.ai/blog/state-of-ai-agent-memory-2026)
- [MemOS — Memory OS for AI](https://statics.memtensor.com.cn/files/MemOS_0707.pdf)
- [Letta — Agent Memory](https://www.letta.com/blog/agent-memory)
- [Tim Kellogg — Memory Patterns 2026](https://timkellogg.me/blog/2026/04/27/memory-patterns)
- [Hermes Self-Improving Agent](https://saulius.io/blog/hermes-agent-self-improving-ai-architecture)
- [memsearch by Zilliz](https://github.com/zilliztech/memsearch)
- [Vertex AI Memory Revisions](https://docs.cloud.google.com/agent-builder/agent-engine/memory-bank/revisions)
- [G-Memory (NeurIPS 2025)](https://neurips.cc/virtual/2025/poster/116187)
- [MemoriesDB — Temporal-Semantic-Relational](https://arxiv.org/html/2511.06179)
- [Zep — Temporal KG Architecture](https://arxiv.org/abs/2501.13956)
- [Graphiti by Zep](https://github.com/getzep/graphiti)
- [SimpleMem (arxiv 2601.02553)](https://arxiv.org/html/2601.02553)
- [LightMem (arxiv 2604.07798)](https://arxiv.org/html/2604.07798)
- [LongMemEval benchmark](https://arxiv.org/pdf/2410.10813)
- [LoCoMo benchmark](https://snap-research.github.io/locomo/)
- [Memanto — SOTA on LongMemEval/LoCoMo](https://arxiv.org/html/2604.22085)
- [Vectorize — Agent Memory Manifesto 2026](https://hindsight.vectorize.io/blog/2026/03/23/agent-memory-benchmark)
- [Intelligent Forgetting (DEV)](https://dev.to/sudarshangouda/ai-agent-memory-part-2-the-case-for-intelligent-forgetting-4i48)
- [LINK-KG — Coreference-Resolved KGs](https://arxiv.org/html/2510.26486)
- [VelvetShark OpenClaw Memory Masterclass](https://velvetshark.com/openclaw-memory-masterclass)
- [Privacy in AI Agent Memory (New America)](https://www.newamerica.org/oti/briefs/ai-agents-and-memory/)

### Retrieval
- [HyDE original](https://arxiv.org/abs/2212.10496)
- [Haystack HyDE](https://docs.haystack.deepset.ai/docs/hypothetical-document-embeddings-hyde)
- [LangChain Query Transformations](https://blog.langchain.com/query-transformations/)
- [Step-Back Prompting (DeepMind)](https://arxiv.org/abs/2310.06117)
- [RAG-Fusion (arxiv 2402.03367)](https://arxiv.org/abs/2402.03367)
- [Self-RAG paper](https://arxiv.org/abs/2310.11511)
- [Microsoft GraphRAG](https://microsoft.github.io/graphrag/)
- [ColBERT — arxiv 2004.12832](https://arxiv.org/abs/2004.12832)
- [ColBERTv2](https://arxiv.org/abs/2112.01488)
- [RAFT — arxiv 2403.10131](https://arxiv.org/abs/2403.10131)

### Multi-agent
- [Anthropic — Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Claude blog — When to use multi-agent](https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them)
- [OpenAI Swarm](https://github.com/openai/swarm)
- [OpenAI Cookbook — Orchestrating Agents](https://cookbook.openai.com/examples/orchestrating_agents)
- [AutoGen GroupChat](https://microsoft.github.io/autogen/stable//user-guide/core-user-guide/design-patterns/group-chat.html)
- [CrewAI Hierarchical Process](https://docs.crewai.com/en/learn/hierarchical-process)
- [CrewAI Flows](https://docs.crewai.com/en/concepts/flows)
- [MetaGPT — Meta Programming for MAS](https://arxiv.org/abs/2308.00352)
- [Reflexion paper](https://arxiv.org/abs/2303.11366)
- [Voting or Consensus? (ACL 2025)](https://aclanthology.org/2025.findings-acl.606/)
- [ACC-Debate Actor-Critic](https://arxiv.org/html/2411.00053v1)
- [Strands Agents — Agents as Tools](https://strandsagents.com/docs/user-guide/concepts/multi-agent/agents-as-tools/)
- [Devin 2.0 (Cognition)](https://cognition.ai/blog/devin-2)
- [Multi-Agent Blackboard System](https://arxiv.org/pdf/2510.01285)

### Координация и надёжность
- [Saga pattern (microservices.io)](https://microservices.io/patterns/data/saga.html)
- [Azure — Saga & Compensation](https://learn.microsoft.com/en-us/azure/architecture/patterns/saga)
- [Idempotent AI Agents (BuildMVPFast)](https://www.buildmvpfast.com/blog/idempotent-ai-agent-retry-safe-patterns-production-workflow-2026)
- [Portkey — Circuit Breakers in LLM apps](https://portkey.ai/blog/retries-fallbacks-and-circuit-breakers-in-llm-apps/)
- [Vercel AI SDK — Backpressure](https://ai-sdk.dev/docs/advanced/backpressure)
- [Event Sourcing (Azure)](https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing)
- [LangGraph Persistence & Time-Travel](https://docs.langchain.com/oss/python/langgraph/persistence)

### Anti-patterns и эвалюация
- [Multi-Agent Overkill (Agent Patterns)](https://www.agentpatterns.tech/en/anti-patterns/multi-agent-overkill)
- [The Multi-Agent Trap (TDS)](https://towardsdatascience.com/the-multi-agent-trap/)
- [Galileo — Coordination Gone Wrong (10 strategies)](https://galileo.ai/blog/multi-agent-coordination-strategies)
- [Counterfactual Evaluation (Eugene Yan)](https://eugeneyan.com/writing/counterfactual-evaluation/)
- [Cobus Greyling — Pareto Frontier for Agents](https://cobusgreyling.medium.com/the-pareto-frontier-for-ai-agents-fa477eaaac6e)

### Тренды апреля 2026
- [A2A Protocol v1.2 (Google Cloud)](https://cloud.google.com/blog/products/ai-machine-learning/agent2agent-protocol-is-getting-an-upgrade)
- [A2A Github](https://github.com/a2aproject/A2A)
- [CrewAI — 2B executions](https://blog.crewai.com/lessons-from-2-billion-agentic-workflows/)
- [LazyGraphRAG (Microsoft Research)](https://www.microsoft.com/en-us/research/project/graphrag/)
- [LangGraph 2026 Edition (Medium)](https://medium.com/@dewasheesh.rana/langgraph-explained-2026-edition-ea8f725abff3)

### OpenClaw-specific
- [OpenClaw Memory docs](https://docs.openclaw.ai/concepts/memory)
- [OpenClaw Multi-Agent docs](https://docs.openclaw.ai/concepts/multi-agent)
- [OpenClaw Memory Management (Mem0)](https://mem0.ai/blog/openclaw-memory-management-live-data-compaction-and-best-practices)
- [Best OpenClaw Memory Configurations 2026](https://www.openclawplaybook.ai/guides/best-openclaw-memory-configurations/)
