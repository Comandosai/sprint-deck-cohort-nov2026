# Блок 19: Lobster workflows (детерминированные процессы в OpenClaw)

> **Что:** Lobster — нативный для OpenClaw workflow-shell: типизированные (JSON/YAML-first) пайплайны, шаги-команды и approval-gates. Превращает скиллы и инструменты в композируемые, повторяемые, аудит-трекируемые автоматизации.
> **Зачем:** Сделать сценарий «Разбери почту» (и другие чувствительные операции) **одним детерминированным вызовом** с явными точками подтверждения вместо хрупкой цепочки чат-сообщений к LLM.
> **Время:** 1–1.5 часа на первый workflow, ~30 минут на каждый последующий.

---

## 🎯 Цель блока

К концу блока ты должен:

1. Понимать, **что Lobster — это shell поверх OpenClaw-инструментов**, а не отдельный сервис. Он живёт в одном процессе с gateway, без сабпроцессов, без сетевых вызовов из плагина.
2. Создать первый workflow в `workspace/lobster/inbox-triage.lobster` (или `.yaml`).
3. Прописать шаги: `collect → categorize → approve → execute`, с pipe `stdin: $step.stdout`.
4. Настроить **approval-gate**, который ставит workflow на паузу и возвращает `resumeToken`. Бот пишет тебе в Telegram «Удалить 17 писем? [Да/Нет]» — клик «Да» вызывает `action: resume` с этим токеном.
5. Запустить тест end-to-end: бот собрал → классифицировал → ждал твоего «да» → удалил. Получить аудит-лог в `~/.openclaw/lobster/runs/<run-id>.json`.
6. Понимать **разницу с n8n (Блок 17), Temporal, Inngest, Trigger.dev** и где у каждого граница применимости.

---

## ⚡ Что нового в апреле 2026

- **OpenClaw 2026.4.26** (28 апр) и **2026.4.25** (27 апр) — последние релизы на момент написания. ([Releasebot](https://releasebot.io/updates/openclaw))
- Exec-approvals теперь принимают `runtime-owned source: 'allow-always'` — можно помечать команды, которые **никогда** не должны спрашивать (например, `ls`, `cat`).
- **Node approval-plan synthesis** — на хостах без поддержки prepare-фазы Lobster всё равно умеет строить план одобрений до выполнения. То есть ты видишь «вот что я СОБИРАЮСЬ сделать», а не «вот что я УЖЕ начал делать».
- Изолированный cron-run в отдельном «agent-turn lane» — пересечения cron-задач больше не ломают активную сессию.
- **OpenTelemetry-расширение** на model calls, tool loops, delivery, memory — каждый шаг workflow теперь экспортируется в OTLP-collector если он подключен.
- Команда `openclaw cron edit --failure-alert-include-skipped` — алерты приходят, даже если задача была пропущена.
- **Cold persisted plugin registry** ускорил старт workflow на 30–60% (по сравнению с зимой 2026). [VERIFY на твоей машине через `time openclaw lobster run …`]

---

## 🛠️ Конкретные инструменты и версии

| Компонент | Версия / Источник | Что делает |
|---|---|---|
| OpenClaw core | 2026.4.26 | Хост-процесс, в котором живёт Lobster |
| Lobster (плагин) | встроен в core, включается через `tools.alsoAllow: ["lobster"]` | Workflow-shell |
| `openclaw.invoke` | shim внутри Lobster | Вызов любого OpenClaw-инструмента из шага |
| `llm-task` plugin | `plugins.entries.llm-task.enabled: true` | Структурированные LLM-шаги внутри workflow |
| Storage | `~/.openclaw/lobster/` (sqlite + json runs) [VERIFY точный путь] | State persistence + журнал runs |
| Workspace | `workspace/lobster/*.lobster` или `*.yaml` | Файлы воркфлоу под Git |
| CLI | `openclaw lobster run <file>` / `openclaw lobster resume <token>` | Запуск и ресюм |
| `graph` команда | `openclaw lobster graph inbox-triage.lobster --format mermaid` | Визуализация |
| `doctor` | `openclaw lobster doctor` | Health-check движка |

Источники: [docs.openclaw.ai/tools/lobster](https://docs.openclaw.ai/tools/lobster), [github.com/openclaw/lobster](https://github.com/openclaw/lobster).

---

## 💡 Лайфхаки и про-приёмы

1. **Lobster — это не «ещё один n8n», это shell поверх OpenClaw-инструментов.** Все skills, MCP, gmail, fs/exec — уже доступны как команды. Не пиши обвязку — пиши пайплайн. Если в одной сессии ты три раза просил бота сделать то же самое — это кандидат в `.lobster`.

2. **Храни workflow-ы под Git.** Папка `workspace/lobster/` коммитится. Каждый PR с workflow проходит код-ревью как обычный код. Аудит «кто и когда добавил `rm -rf`» работает прямо из `git blame`.

3. **Используй `args` и `LOBSTER_ARG_<NAME>` env-переменные** для параметризации. Один файл `inbox-triage.lobster` принимает `tag=family` или `tag=work` — не дублируй файлы.

4. **`stdin: $step.stdout` лучше, чем temp-файлы.** Меньше IO, меньше гонок, всё видно в логе. Используй `$step.json` если нужен распарсенный JSON, а не сырой stdout.

5. **Approval-gate возвращает `resumeToken` — сохрани его в Telegram-кнопке.** Inline-keyboard `callback_data` = `resume:<token>:yes` / `resume:<token>:no`. Бот ловит callback → дёргает `lobster resume`. Это нативный паттерн, а не костыль.

6. **`required_approver` и `require_different_approver`** — для команды. `required_approver: dmitriy@…` гарантирует, что approval может дать только Дмитрий. `require_different_approver: true` запрещает self-approve в pipeline, где первый шаг инициировал ты сам.

7. **`timeout_ms` на каждом шаге, не глобально.** LLM-классификация = 60s, а `mail.delete` = 5s. Глобальный 30s «съест» долгий, но валидный шаг.

8. **`retry: 3` + `on_error: skip|halt|continue`.** Идемпотентность: `mail.delete --id X` можно retry-ить, бот всё равно увидит «уже удалено». А `mail.send` — нельзя без `idempotency_key`.

9. **`approve --preview-from-stdin --limit 5`** — показывай первые 5 строк диффа, а не все 200 писем. Telegram-сообщение и так будет длинным.

10. **`openclaw lobster graph … --format mermaid` для код-ревью.** Mermaid-диаграмма из workflow → вставляешь в PR-описание. Ревьюер видит DAG, а не только YAML.

11. **`pipeline:` (нативные стейджи) быстрее, чем `run:` (shell).** `where`, `pick`, `head`, `json`, `table` — встроенные рендереры. Не вызывай `jq` через shell, если можно `pick .messages[]`.

12. **`llm-task` для структурированного вывода.** `schema: {type: object, properties: {…}}` гарантирует JSON. Сравни: чат-промпт «верни JSON» работает в 90% случаев, `llm-task` — в 99.9%, потому что schema валидируется до возврата.

13. **`when: $previous.exit_code == 0`** для условных ветвей. Не делай всё через `&&` в одной команде — теряется наблюдаемость.

14. **Для параллельных шагов — `parallel: true` в группе шагов** [VERIFY синтаксис в твоей версии — в 2026.4.x появилось, но семантика «fork/join» документирована не всегда явно].

15. **Audit-log хранится в `~/.openclaw/lobster/runs/<run-id>.json`.** Туда пишется кто инициировал, кто одобрил, какие были stdout/stderr, сколько по времени. Для compliance — экспортируй раз в неделю в S3.

16. **Lobster ≠ cron.** Lobster запускает workflow. Чтобы он запускался по расписанию — оборачивай в `openclaw tasks flow` (Task Flow) или внешний cron, который делает `openclaw lobster run …`.

17. **Не клади секреты в YAML.** `env: { TOKEN: $SECRET_NAME }` — Lobster резолвит из системного secrets-store, а не из файла. Файл идёт в Git.

18. **`approval: required` без preview — антипаттерн.** Всегда показывай, что одобряешь. Иначе approval превращается в muscle-memory «ОК», и человек случайно удаляет inbox.

---

## 📋 Готовые команды и конфиги

### Включить Lobster (один раз)

В `~/.openclaw/openclaw.json`:

```json
{
  "tools": {
    "alsoAllow": ["lobster"]
  },
  "plugins": {
    "entries": {
      "llm-task": { "enabled": true }
    }
  }
}
```

Перезапуск: `openclaw restart`. Проверка: `openclaw lobster doctor`.

### Папка workflow-ов

```bash
mkdir -p ~/clawd/workspace/lobster
cd ~/clawd/workspace/lobster
git init && git add . && git commit -m "lobster: bootstrap"
```

### Полный workflow YAML — Email triage с approval-gate

`workspace/lobster/inbox-triage.lobster`:

```yaml
name: inbox-triage
description: |
  Собирает свежие письма за последние N дней, классифицирует через LLM
  (важное / спам / промо / можно удалить), показывает превью пользователю
  и удаляет только после подтверждения.

args:
  since:
    default: "newer_than:1d"
    description: Gmail search query
  tag:
    default: "personal"
  delete_limit:
    default: 50
    description: Максимум писем за один прогон

env:
  TZ: Europe/Moscow
  LOBSTER_LOG_LEVEL: info

steps:

  # ────────── 1. Сбор писем ──────────
  - id: collect
    description: Скачиваем заголовки писем по фильтру
    pipeline: openclaw.invoke --tool gmail.search --args-json '{
        "query": "$LOBSTER_ARG_SINCE",
        "max_results": $LOBSTER_ARG_DELETE_LIMIT,
        "fields": ["id","from","subject","snippet","date"]
      }'
    timeout_ms: 30000
    retry: 2
    on_error: halt

  # ────────── 2. Классификация ──────────
  - id: categorize
    description: LLM-классификация в 4 корзины
    pipeline: openclaw.invoke --tool llm-task --action json --args-json '{
        "model": "claude-opus-4-7",
        "thinking": "low",
        "input": $collect.json,
        "prompt": "Классифицируй письма по полю category в одно из: important | spam | promo | trash. Для каждого письма верни {id, category, reason}.",
        "schema": {
          "type": "object",
          "properties": {
            "decisions": {
              "type": "array",
              "items": {
                "type": "object",
                "required": ["id","category","reason"],
                "properties": {
                  "id":       {"type":"string"},
                  "category": {"enum":["important","spam","promo","trash"]},
                  "reason":   {"type":"string","maxLength":120}
                }
              }
            }
          },
          "required": ["decisions"]
        }
      }'
    stdin: $collect.stdout
    timeout_ms: 60000
    retry: 1
    on_error: halt

  # ────────── 3. Подготовка списка к удалению ──────────
  - id: filter_trash
    description: Оставляем только category=trash и promo
    pipeline: pick .decisions[] | where '.category == "trash" or .category == "promo"' | json
    stdin: $categorize.json
    timeout_ms: 5000

  # ────────── 4. Approval gate ──────────
  - id: approve_delete
    description: Спрашиваем у Дмитрия подтверждение в Telegram
    approval: required
    required_approver: "dmitriy@example.com"   # подставь свой openclaw user id
    require_different_approver: false           # self-approve тут ок
    pipeline: approve
      --preview-from-stdin
      --limit 5
      --prompt 'Удалить $count писем (trash + promo) из Gmail? Превью первых 5 ниже.'
      --channel telegram
    stdin: $filter_trash.stdout
    timeout_ms: 3600000   # ждём человека до 1 часа
    on_error: halt

  # ────────── 5. Удаление (только после approve) ──────────
  - id: execute_delete
    description: Помещаем в корзину Gmail (НЕ permanent delete)
    when: $approve_delete.approved == true
    pipeline: openclaw.invoke --tool gmail.batch_trash --args-json '{
        "ids": $filter_trash.json | pick .[].id
      }'
    stdin: $filter_trash.stdout
    timeout_ms: 30000
    retry: 3
    on_error: continue   # если 1 письмо не удалилось — продолжаем

  # ────────── 6. Финальный отчёт ──────────
  - id: report
    description: Шлём в Telegram итог
    pipeline: openclaw.invoke --tool telegram.send --args-json '{
        "text": "Inbox triage готов. Удалено: $execute_delete.count. Важных оставлено: $categorize.important_count. Run-id: $LOBSTER_RUN_ID"
      }'
    on_error: skip   # если Telegram упал — не падаем
```

### Запуск

```bash
# Сухой прогон (план, без выполнения)
openclaw lobster run workspace/lobster/inbox-triage.lobster --dry-run

# Реальный прогон с аргументами
openclaw lobster run workspace/lobster/inbox-triage.lobster \
  --args-json '{"since":"newer_than:3d","tag":"work","delete_limit":100}'

# Когда Telegram-кнопка нажата → бот вызывает:
openclaw lobster resume --token <resumeToken> --approve true

# Визуализация
openclaw lobster graph workspace/lobster/inbox-triage.lobster --format mermaid > inbox.mmd

# Health-check
openclaw lobster doctor

# История run-ов
ls -lt ~/.openclaw/lobster/runs/ | head
cat ~/.openclaw/lobster/runs/<run-id>.json | jq .
```

### Output envelope (что возвращает Lobster в OpenClaw)

```json
{
  "status": "needs_approval",
  "step_id": "approve_delete",
  "requiresApproval": {
    "resumeToken": "lob_8f3a…",
    "preview": "5 писем: 'Sale -50%', 'Newsletter #41', …",
    "prompt": "Удалить 17 писем (trash + promo)?",
    "expires_at": "2026-04-29T15:30:00Z"
  }
}
```

После `resume` со «yes»:

```json
{
  "status": "ok",
  "run_id": "run_2026-04-29_…",
  "steps": [
    {"id": "collect",        "duration_ms": 412,  "exit_code": 0},
    {"id": "categorize",     "duration_ms": 4287, "exit_code": 0},
    {"id": "filter_trash",   "duration_ms": 18,   "exit_code": 0},
    {"id": "approve_delete", "duration_ms": 47000,"approved": true, "approver": "dmitriy"},
    {"id": "execute_delete", "duration_ms": 1340, "deleted_count": 17},
    {"id": "report",         "duration_ms": 220,  "exit_code": 0}
  ]
}
```

---

## ⚠️ Подводные камни

1. **`approval: required` без `timeout_ms` = вечная пауза.** Дефолт мог бы быть «бесконечно». Всегда ставь явный таймаут (1–24 часа).
2. **`resumeToken` имеет TTL.** Если человек ответил через сутки — токен может протухнуть. Lobster хранит state, но настрой TTL под свои сценарии.
3. **`gmail.batch_trash` идемпотентен**, а вот `gmail.permanent_delete` — нет. Никогда не ставь permanent в auto-pipeline без двойного approve.
4. **YAML-anchor для длинных промптов лучше, чем встроенный JSON.** Иначе экранирование кавычек убивает мозг.
5. **`stdin: $step.json` ≠ `stdin: $step.stdout`.** Первый — распарсенный JSON, второй — сырой текст. Перепутаешь — пайп сломается тихо.
6. **OpenClaw тулзы могут сменить имена** между минорными версиями (`gmail.search` vs `gog.gmail.search`). Закрепляй в README рабочую версию OpenClaw.
7. **`llm-task` стоит токенов.** Если запускаешь triage каждый час — посчитай: 100 писем × 4 раза в день × 30 дней = 12k LLM-классификаций. Включи кэш по subject hash.
8. **Local execution only** — Lobster не делает сетевых вызовов сам. Если нужно ходить в HTTP — это делает OpenClaw-tool, который ты вызываешь.
9. **`condition` vs `when` — синонимы**, но в одном файле выбери один стиль. Иначе ревью утонет в придирках.
10. **Audit log не ротируется автоматически** [VERIFY на 2026.4.x]. Раз в месяц чисти `~/.openclaw/lobster/runs/` или настрой logrotate.
11. **Параллельные шаги делят rate-limit** OpenClaw-инструмента. 5 параллельных `gmail.search` = 5x токенов в Google API.
12. **`approve --channel telegram` требует подключённого Telegram-плагина** (Блок 4). Иначе approval уходит «в никуда» и тулза висит.

---

## ✅ Чек-лист выполнения

- [ ] OpenClaw обновлён до 2026.4.26+ (`openclaw --version`)
- [ ] В `openclaw.json` добавлено `tools.alsoAllow: ["lobster"]`
- [ ] `openclaw lobster doctor` возвращает все зелёные
- [ ] Создана папка `workspace/lobster/` под Git
- [ ] Написан `inbox-triage.lobster` с 6 шагами
- [ ] `--dry-run` показывает корректный план
- [ ] Реальный прогон останавливается на approve_delete
- [ ] В Telegram пришло сообщение с превью и кнопками Yes/No
- [ ] Клик «Yes» → Lobster выполнил `execute_delete`
- [ ] В `~/.openclaw/lobster/runs/<run-id>.json` лежит полный лог
- [ ] Workflow закоммичен в Git с осмысленным сообщением
- [ ] Mermaid-диаграмма экспортирована и приложена в README
- [ ] Создан второй workflow (например, weekly-report) — для повторяемости опыта
- [ ] (опц.) OpenTelemetry-collector подключён, метрики идут

---

## 🧪 Верификация

1. **Дрифт-тест.** Запусти один и тот же workflow дважды с одинаковыми args. Run-id разный, но порядок шагов и контракты — идентичны. Если есть случайность — где-то LLM без `temperature: 0`.
2. **Approval-bypass-тест.** Жми «No» в Telegram. Workflow должен вернуть `status: cancelled`, шаг `execute_delete` не выполниться. Проверь `gmail.search` — письма на месте.
3. **Timeout-тест.** Поставь `approve_delete.timeout_ms: 60000`, не нажимай ничего. Через минуту workflow завершится с `cancelled` и причиной `approval_timeout`.
4. **Idempotency-тест.** Удали то же письмо вручную через web Gmail, потом запусти workflow. `execute_delete` с `retry: 3` должен пережить 404-ответ от gmail-tool.
5. **Resume-тест.** Поймай `resumeToken`, перезапусти весь OpenClaw процесс (`systemctl restart openclaw`), затем выполни `lobster resume --token …`. State должен пережить рестарт (sqlite).
6. **Аудит-тест.** Через `git log workspace/lobster/` восстанови, кто менял шаги. Через `~/.openclaw/lobster/runs/` — кто и когда одобрял.
7. **Comparison-test.** Сделай тот же сценарий «руками» через чат-промпт к боту. Замерь: сколько токенов сожрала LLM, сколько было ошибок, сколько раз бот забыл одобрение спросить. Lobster должен выиграть на всех трёх.

---

## ⏱ Реальная оценка времени

| Этап | Минут |
|---|---|
| Чтение `docs.openclaw.ai/tools/lobster` | 15 |
| Включение плагина + doctor | 5 |
| Первый `inbox-triage.lobster` (по шаблону выше) | 25 |
| Подключение approval к Telegram | 15 |
| Тестирование dry-run + реальный прогон + resume | 15 |
| Дебаг неминуемых опечаток в YAML | 10 |
| Коммит в Git, mermaid-диаграмма, README | 10 |
| **Итого** | **~95 минут** |

С опытом второй workflow занимает 20–30 минут.

---

## 🔗 Связи с другими блоками

**ДО (нужно сделать раньше):**
- **Блок 8 — Skills.** Lobster вызывает skills через `openclaw.invoke`. Без скиллов — нечего оркестрировать.
- **Блок 4 — Telegram.** Approval-gate отправляет сообщение туда. Без Telegram — нет канала подтверждения.
- **Блок 17 — n8n** (если был). Понимание разницы: n8n — для интеграций между SaaS, Lobster — для оркестрации внутренних OpenClaw-инструментов с approval.

**ПОСЛЕ (опирается на Lobster):**
- **Блок 20 — финальная сборка / прод-гард.** Все опасные операции (delete, send, transfer) обёрнуты в `.lobster` с approval. Чат больше не дёргает их напрямую.

**Сравнительная карта (когда что):**

| Кейс | Инструмент |
|---|---|
| «Каждый день в 9:00 проверь почту, удали мусор с моего одобрения» | **Lobster + cron-обёртка** |
| «Когда новый клиент в Stripe — добавь в Notion + Slack» | **n8n** (визуальный, много интеграций) |
| «Платёжный пайплайн с saga, retry, 30-дневной длительностью» | **Temporal** (durable execution) |
| «Event-driven serverless, Vercel/Next.js» | **Inngest / Trigger.dev** |
| «Background jobs внутри Node.js монолита, Redis уже есть» | **BullMQ** |
| «Простой одноразовый скрипт» | **Bash / `openclaw exec`** — не плоди workflow ради 3 строк |

Граница: **Lobster выигрывает там, где центральный актёр — OpenClaw-агент** и нужны approval-gates с участием человека через Telegram. n8n выигрывает на интеграциях между внешними SaaS. Temporal — для финансово-критичной долгоживущей оркестрации.

---

## 📚 Источники

- [docs.openclaw.ai/tools/lobster](https://docs.openclaw.ai/tools/lobster) — официальная спецификация
- [github.com/openclaw/lobster](https://github.com/openclaw/lobster) — README, схема, примеры
- [docs.openclaw.ai](https://docs.openclaw.ai) — общая документация OpenClaw
- [openclaw.ai](https://openclaw.ai) — описание продукта
- [Releasebot — OpenClaw April 2026](https://releasebot.io/updates/openclaw) — релиз-ноты 2026.4.25/26
- [DEV.to — Deterministic multi-agent dev pipeline в Lobster](https://dev.to/ggondim/how-i-built-a-deterministic-multi-agent-dev-pipeline-inside-openclaw-and-contributed-a-missing-4ool) — реальный кейс
- [QuantumByte — How people use OpenClaw workflows in 2026](https://quantumbyte.ai/articles/how-people-use-openclaw-workflows-in-2026)
- [Skywork — Ultimate Guide to OpenClaw Lobster](https://skywork.ai/skypage/en/openclaw-lobster-guide/2037014641565765632)
- [Inngest vs Temporal сравнение 2026](https://www.inngest.com/compare-to-temporal)
- [Temporal vs n8n 2026](https://openalternative.co/compare/n8n/vs/temporal)
- [OpenClaw vs n8n — Blink](https://blink.new/blog/openclaw-vs-n8n-comparison-2026)
- [Medium — n8n vs Claude CoWork vs OpenClaw, апрель 2026](https://medium.com/design-bootcamp/building-agents-n8n-vs-claude-cowork-vs-openclaw-d6f3ea019bb6)

[VERIFY] — отметки на пунктах, которые не удалось 100% подтвердить через docs (точный путь sqlite, синтаксис `parallel: true`, ротация audit-log) — проверь на своей версии OpenClaw перед прод-использованием.
