# Execution Log — Воркшоп 2 (тестовый прогон)

> Журнал реальных находок при прохождении В2. По итогам прогона —
> обновим `standards/workshop-2-standard.md` до v1.1 (или v1.9.0 deck'a).
> Сюда AI-агент не пишет — это **мой** журнал на основе отчётов которые
> присылает Дмитрий после каждого Промпта.

---

## OpenClaw версия

`2026.4.29` — фиксируем.

---

## Расхождения standards/workshop-2-standard.md ↔ реальная schema

### 🔴 Раздел A — Архитектура памяти

_(отчёт получен в общем потоке, явные расхождения не зафиксированы; A.1–A.7 закрыты в Промпте 2)_

---

### 🔴 Раздел C — Постоянная память (Qdrant + Mem0 + Privacy)

**Из отчёта AI после Промпта 4:**

#### Что реально работает «как обещано»
- C.1–C.4 Qdrant healthy на 127.0.0.1:6333, qdrant/qdrant:v1.12.4 (фикс), restart unless-stopped, healthcheck — всё ровно по стандарту
- C.6 collection `openclaw_main`, vector_size=1536, status=green, 35 points (35!)
- C.7 embedder: text-embedding-3-small (выбор Дмитрия — OpenAI), API key в `~/.openclaw/secrets/api-keys.env` chmod 600
- C.13–C.16 privacy guard работает: 13 regex + LLM-classifier на gemini-flash-lite, blockOnDetect (не маскируем). Тесты прошли (JWT/AKIA/ИНН блокированы; «Анна Сбер 100k» прошёл).

#### 🚨 Серьёзные расхождения стандарта со schema/SDK

| В стандарте | Реальность Mem0 SDK 2.x |
|---|---|
| **C.5** «Mem0 SDK подключён через `openclaw skills install mem0`» | ❌ Официального плагина для openclaw НЕТ. Mem0 ставится через **pip+venv** (`~/.openclaw/mem0/venv/`, mem0ai 2.0.2). `openclaw skills list \| grep mem` даёт false positives (memo+member). |
| **C.8** «Hybrid search vec/BM25 0.7/0.3» | ⚠️ Mem0 SDK 2.x **не экспонирует** vectorWeight/textWeight knobs. Чисто vec-search. Чтобы реально hybrid 0.7/0.3 — нужен bypass-модуль через `qdrant_client.search()` напрямую. |
| **C.9** «MMR lambda 0.7» | ⚠️ Не экспонирован в Mem0 SDK 2.x |
| **C.10** «TemporalDecay halfLifeDays 30» | ⚠️ Не экспонирован. Эмулируется через metadata.timestamp + post-фильтр в коде. |
| **C.11** «Reranker bge-reranker-v2-m3» | ❌ Mem0 SDK 2.x не имеет встроенного reranker pipeline. Можно добавить отдельным шагом после `mem.search()` (~100+ строк кода). Отложено в В3. |
| **C.12** «Auto-capture true» | ⚠️ Не из коробки Mem0 — AI написал собственный **memory-watcher daemon** (systemd-user, тейлит `~/.openclaw/agents/main/sessions/*.trajectory.jsonl` и через privacy guard прогоняет в Qdrant). Уже работает: 17 → 35 points за минуты. |

#### Артефакты которые AI задеплоил (нет в стандарте — нужно добавить)

| Путь | Что |
|---|---|
| `~/.openclaw/qdrant/docker-compose.yml` | Qdrant compose |
| `~/.openclaw/mem0/venv/` | Python venv (mem0ai 2.0.2 + qdrant-client + fastembed + openai) |
| `~/.openclaw/mem0/openclaw_memory.py` | CLI glue (seed/recall/add/status/privacy-test) |
| `~/.openclaw/scripts/memory.sh` | Shell shim — используется ВМЕСТО `openclaw memory recall` |
| `~/.openclaw/mem0/memory_watcher.py` | Auto-capture daemon |
| `~/.config/systemd/user/memory-watcher.service` | systemd unit (active, enabled) |
| `~/.openclaw/secrets/api-keys.env` | OpenAI ключ для embedder, chmod 600 |

#### Команды на случай факапа (зафиксировать в RECOVERY.md):
- Mem0 заглючил: `systemctl --user stop memory-watcher; docker compose -f ~/.openclaw/qdrant/docker-compose.yml restart`
- Посмотреть данные: `curl http://127.0.0.1:6333/collections/openclaw_main`
- Recall: `~/.openclaw/scripts/memory.sh recall "<вопрос>"`
- Watcher лог: `tail -f ~/.openclaw/mem0/watcher.log`

#### 🎯 Бонус-наблюдение
Auto-capture **уже подхватил B.11-диалог** про «Тестова» из trajectory.jsonl без участия Дмитрия. Recall возвращает scores 0.37-0.40 на нечётких запросах «что у меня за проект» — для русского ОК.

---

### 🔴 Раздел B — Защита контекста

**Из отчёта AI после Промпта 3:**

| В стандарте | В реальной schema 2026.4.29 | Реальный эквивалент |
|---|---|---|
| `compaction.enabled: true` | ❌ **нет такого ключа** | Compaction всегда работает. Эквивалент — `compaction.mode: "safeguard"` (строже default, регенерирует саммари при провале quality-audit) |
| `compaction.softThresholdTokens: 40000` | ❌ нет ключа | `compaction.keepRecentTokens: 8000` (последние ~40 сообщений verbatim) + `compaction.recentTurnsPreserve: 3` |
| `compaction.hardThresholdTokens: 80000` | ❌ нет ключа | `compaction.maxHistoryShare: 0.5` (история ≤50% бюджета) + `compaction.truncateAfterCompaction: true` |
| `compaction.strategy: "summarize-middle"` | ❌ нет ключа | Это и есть **единственная** built-in стратегия. Не нужно настраивать. |
| `compaction.preserveTags: ["decision", "fact", ...]` | ❌ нет ключа | Через `compaction.customInstructions` строкой: «Preserve verbatim any content tagged `<decision>`, `<fact>`, `<action-required>`...» |
| `compaction.summarizerModel` | ✅ есть как `compaction.model` | прямое соответствие |
| `compaction.memoryFlush.softThresholdTokens` | ✅ есть | в стандарте писалось 4000, AI поставил 8000 — реальнее |

**Реальные ключи compaction в 2026.4.29 (по `openclaw config schema`):**
```
compaction.{
  mode,                        // "safeguard" | "default" | ...
  model,                       // summarizerModel из стандарта
  keepRecentTokens,            // вместо softThresholdTokens
  recentTurnsPreserve,
  reserveTokens,
  maxHistoryShare,             // вместо hardThresholdTokens
  customInstructions,          // вместо preserveTags
  truncateAfterCompaction,
  memoryFlush.{ enabled, model, softThresholdTokens }
}

contextPruning.{ mode, ttl, keepLastAssistants }
agents.defaults.contextInjection
```

**Что AI применил по Промпту 3:**
```json
{
  "agents": {
    "defaults": {
      "compaction": {
        "mode": "safeguard",
        "model": "openrouter/moonshotai/kimi-k2.6",
        "keepRecentTokens": 8000,
        "recentTurnsPreserve": 3,
        "maxHistoryShare": 0.5,
        "truncateAfterCompaction": true,
        "customInstructions": "Preserve verbatim any content tagged <decision>, <fact>, or <action-required>...",
        "memoryFlush": {
          "enabled": true,
          "model": "openrouter/moonshotai/kimi-k2.6",
          "softThresholdTokens": 8000
        }
      },
      "contextPruning": {
        "mode": "cache-ttl",
        "ttl": "5m",
        "keepLastAssistants": 2
      },
      "contextInjection": "continuation-skip"
    }
  }
}
```

✅ Все 11 пунктов B.1–B.11 закрыты или эквивалентом:
- B.4 (summarize-middle) — implicit (built-in)
- B.6 (preserveTags) — через customInstructions
- B.11 (тест 3 сообщений) — нужен ручной прогон Дмитрия

---

### 🔴 Раздел G — Доделки В1

**Из отчёта AI после Промпта 1:**

| Пункт | Что AI применил |
|---|---|
| G.1 heartbeat на flash-lite | `heartbeat.{every:"60m", model:"openrouter/google/gemini-2.5-flash-lite", session:"isolated"}` — `lightContext` и `isolatedSession` из стандарта **не существуют** в schema 2026.4.29, использован `session: "isolated"` |
| G.2 prompt caching | Глобального toggle НЕТ. В schema есть `cost.cacheRead` / `cost.cacheWrite` per provider (для MiniMax уже задано 0.06/0.375). Hit rate замеряется через `openclaw logs --grep cache` после прогрева 5 одинаковыми запросами. |
| G.3 нет timestamps в SOUL/USER/IDENTITY | `grep -nE "[0-9]{4}-[0-9]{2}-[0-9]{2}"` пусто. ✅ |
| G.4 chmod 600 | `stat -c "%a" openclaw.json` → 600 ✅ |
| G.5 watchdog для прав | Создан `~/.openclaw/scripts/chmod-watchdog.sh` + cron `0 4 * * *` ✅ |
| G.6 привычка restart | Создан `~/.openclaw/scripts/apply-config.sh` (doctor → systemctl restart openclaw-gateway → chmod 600) ✅ |
| G.7 /context list, /usage full | Зарегистрированы в getMyCommands. Нужен ручной клик в TG. |
| G.8 сверка моделей | **flux-schnell мёртв** на OpenRouter — заменён на `openrouter/google/gemini-3.1-flash-image-preview`. Остальные slugs живые. |
| G.9 ackReaction 👀 | ✅ |

**🚨 КРИТИЧНАЯ НАХОДКА для всех будущих промптов:**
> «`config patch` — единственный безопасный способ менять openclaw.json. Прямое редактирование руками + `doctor --fix` сейчас может молча стирать ключи которых нет в schema. Скрипт `apply-config.sh` это закрывает но в нём нет `config patch`.»

→ Все следующие промпты должны явно говорить AI: «используй `openclaw config patch --file ... --dry-run` потом без --dry-run».

---

## Что обновить в стандарте В2 после прохождения

### Стандарт В2 → v1.1

**1. Раздел A** — _ждём отчёта от Промпта 2_

**2. Раздел B** — переписать целиком на реальные ключи schema 2026.4.29:
- B.1 `compaction.mode: "safeguard"` (вместо `enabled: true`)
- B.2 `keepRecentTokens: 8000` + `recentTurnsPreserve: 3` (вместо `softThresholdTokens: 40000`)
- B.3 `maxHistoryShare: 0.5` + `truncateAfterCompaction: true` (вместо `hardThresholdTokens: 80000`)
- B.4 — убрать (built-in, не настраивается)
- B.5 `compaction.model: "openrouter/moonshotai/kimi-k2.6"` ✅ как было
- B.6 `compaction.customInstructions: "Preserve verbatim any content tagged..."` (вместо `preserveTags: [...]`)
- B.7–B.8 ✅ как было, добавить `memoryFlush.softThresholdTokens: 8000`

**2.5. Раздел C** — переписать целиком:
- C.5 — «Mem0 ставится через pip+venv в `~/.openclaw/mem0/venv/`» (НЕ через `openclaw skills install`)
- C.8/C.9/C.10/C.11 — пометить как **«в Mem0 SDK 2.x не экспонировано — отложено в В3 через bypass-модуль»**. Остаётся базовый vec-search.
- C.12 — добавить артефакт `memory_watcher.py` + systemd unit (это not-out-of-box, AI пишет сам)
- Дать готовый шаблон `openclaw_memory.py` + `memory_watcher.py` в репо как референс

**3. Раздел G** — обновить:
- G.1 — добавить `session: "isolated"` (`lightContext` и `isolatedSession` из стандарта **не существуют**)
- G.2 — переформулировать: «`cost.cacheRead/cacheWrite` per provider настроены (для MiniMax 0.06/0.375); hit rate ≥60% через 5 одинаковых запросов»
- G.5 — упомянуть готовый шаблон `chmod-watchdog.sh`
- G.6 — упомянуть готовый шаблон `apply-config.sh`
- G.8 — `flux-schnell` мёртв, замена → `openrouter/google/gemini-3.1-flash-image-preview` (это попадает в стандарт В1 E.3 тоже!)

**4. Стандарт В1 E.3 → правка**
- было `openrouter/black-forest-labs/flux-schnell` (мёртвый slug)
- стало `openrouter/google/gemini-3.1-flash-image-preview`

### Гайд В2 → v2.1

**1. Промпт #0** добавить правило:
> «Для редактирования openclaw.json используй ТОЛЬКО `openclaw config patch --file ... --dry-run` (потом без `--dry-run`). НЕ `jq` напрямую и НЕ ручное редактирование — `doctor --fix` молча стирает ключи которых нет в schema 2026.4.29.»

**2. Промпт #0** добавить упоминание готовых скриптов:
> «У тебя уже есть `~/.openclaw/scripts/apply-config.sh` (создан в В1 если ты первый раз — создай). Используй его вместо ручных вызовов doctor+restart+chmod.»

**3. Промпт 3** обновить — реальные ключи compaction (см. выше)

---

## Лог тестов которые делает Дмитрий вручную

| Тест | Промпт | Статус | Результат |
|---|---|---|---|
| Прогрев кэша (5 одинаковых запросов) | G.2 | ⏳ ожидание | — |
| `/context list` + `/usage full` в TG | G.7 | ⏳ ожидание | — |
| 3 сообщения подряд (имя/бюджет/дедлайн) | B.11 | ⏳ ожидание | — |
| Auto-capture тест (3 факта, 5 мин) | D.1 | _не дошло_ | — |
| Amnesia test (после /reset) | D.2 | _не дошло_ | — |

---

## История прогона

| Дата | Промпт | Что сделано | Кто отчитывался |
|---|---|---|---|
| 2026-05-09 | #0 | git pull + чтение стандарта + проверка SSH | Claude Code в VSCode |
| 2026-05-09 | 1 — Доделки В1 (раздел G) | 6/9 ✅, 3 ⚠️ ждут ручных тестов | тот же AI |
| 2026-05-09 | 2 — Архитектура памяти (раздел A) | _отчёт не получил_ | _неизвестно_ |
| 2026-05-09 | 3 — Защита контекста (раздел B) | 10/11 ✅, B.11 ждёт ручного теста | тот же AI |
| 2026-05-09 | B.11 ручной тест | ✅ бот ответил «Тестов / 50k$ / 15 июня» | Дмитрий + бот |
| 2026-05-09 | 4 — Qdrant + Mem0 (раздел C) | C.1–C.7, C.12–C.16 ✅; C.8/9/10/11 — гэпы Mem0 SDK 2.x; auto-capture работает | тот же AI |
| | 5 — Тест auto-capture (D.1) | следующий — но auto-capture уже работает (B.11 подхвачен) | — |
| | 6 — git init + crypt | впереди | — |
| | 7 — GitHub репо + cron | впереди | — |
| | 8 — Гигиена | впереди | — |
| | 9 — Amnesia test + сборка | впереди (главный тест памяти) | — |

---

**Файл-журнал создан 2026-05-09. Запушен в repo вместе с patches v1.3 (2026-05-12).**

---

# 2026-05-12 — Cohort feedback → patches v1.2 + v1.3

После публикации W2 v2.0 (9 мая) когорта Nov-2026 начала прогон. За 3 дня вскрылось 5 проблем — все пропатчены, стандарты обновлены, гайды перепубликованы.

## Что вскрылось у участников

### 🔴 1. Mem0 retrieval не вызывается автоматически (от Григория, 2026.5.6)
- Auto-capture cron пишет в Qdrant ✅
- Ручной `mem0-search.js "<query>"` отдаёт точные факты ✅
- `openclaw skills list` показывает `mem0 ✓ ready` ✅
- **НО LLM сам этот скилл не зовёт** — идёт в `web_search` и фабрикует.

**Доказательство** (строгий D.3 ретест на чисто-Qdrant фактах):
- До фикса: 0/3, в session jsonl `web_search calls=8`, `memory_search calls=0`. Бот придумал «минимум 3 локации» вместо «20» из Qdrant.
- После фикса: 3/3, бот цитирует «Из памяти (2026-05-11)», `web_search=0`, `memory_search=8`.

**Фикс:** секция `Memory Search Protocol — обязательно` в `workspace/AGENTS.md` + дублирующий буллет в `SOUL.md`.

**Стандарт-апдейт:** C.17 ❗ + D.4 ❗ (trajectory.jsonl-проверка реального tool_call).

### 🔴 2. SSH брут-форс на порт 22
- 2-дневная атака с десятка IP. fail2ban с дефолтным `bantime=3600` не справился — атакующие ротировали IP, забивали MaxStartups, AI-агент не мог достучаться.

**Фикс v1.2 (12 мая утром):** A.11-A.14 — смена SSH-порта, PasswordAuth off, fail2ban 24h, MaxStartups/MaxSessions.

**Фикс v1.3 (12 мая вечером):** A.15 ❗ — настоящая защита через **Tailscale** (SSH не торчит в публичный интернет вообще). A.11-A.14 остаются baseline для тех кто без VPN.

### 🟡 3. Permission watchdog слишком редко (раз в сутки)
- Из стандарта `17 4 * * *` ловит chmod 644 регрессию (#18866) с drift-окном до 24h.
- Участник предложил `*/15 * * * *` (≤15 мин).

**Стандарт-апдейт:** F.5 ❗ — watchdog */15.

### 🟡 4. Autocommit мог утечь auth-profiles.json
- Если в скрипте `git add .` или `git add -A` — `agents/main/agent/auth-profiles.json` с plaintext API-ключами уходит в GitHub.

**Стандарт-апдейт:** E.15 ❗ — autocommit whitelist через `stage_workspace_if_exists` + blocklist guard.

### 🟢 5. Версионный дрейф OpenClaw 2026.5.x
- Андрей: «codex сказал что промпты были для одной версии, а сейчас другая встала».
- Mem0 SDK на 2026.5.0+ требует `--dangerously-force-unsafe-install` (issue #4645) — dangerous-code-detection ужесточился.
- MiniMax M2.7 болтлив по характеру модели — нужна агрессивная anti-verbosity секция в SOUL.md.

**Гайд-апдейт:** Промпт 4 (Mem0 install) — нотис про флаг для 2026.5.x. Промпт 3 (compaction) — anti-verbosity SOUL.md.

## Артефакты патчей

### Стандарты
- `standards/workshop-1-standard.md` → **v1.3** (A.11-A.14 baseline hardening + A.15 Tailscale)
- `standards/workshop-2-standard.md` → **v1.1** (C.17, D.4, E.15, F.5)

### Гайды (опубликованы на here.now in-place)
- W1: https://proud-mill-zysx.here.now/ (Tab 06 «🩹 Патчи v1.3» — A.1 Tailscale + A.2 базовый)
- W2: https://eager-kitten-9638.here.now/ (Tab 04 «🩹 Патчи v1.3» — A.1/A.2 + B Memory Search + C watchdog + D whitelist + E anti-verbosity + F dangerous-code bypass)

### Google Docs версии W2
- `workshop-2/google-docs/guide-w2-1-ustanovka.html` — Установка
- `workshop-2/google-docs/guide-w2-2-auditor.html` — Аудитор
- `workshop-2/google-docs/guide-w2-3-sdacha.html` — Сдача

## Принципы для W3+

1. **Verify the call, not the answer** — аудит проверяет ЧТО бот сделал (trajectory.jsonl), а не только ЧТО он ответил. Иначе бот может пройти через injection/fabrication.
2. **No public SSH** — каждый воркшоп должен предполагать Tailscale/zero-trust как baseline, не fallback.
3. **Version-aware prompts** — в Промпт #0 встроить `openclaw --version` и адаптацию команд под мажорную версию. Стандарт не должен быть прибит к конкретной точечной версии.
4. **Whitelist > blocklist для секретов** — `git add .` слишком опасен. Always explicit whitelist + paranoid blocklist guard.

## Deferred → W3

- ⚠️ MiniMax M2.7 болтливость — aggressive SOUL.md помогает, но не лечит окончательно. В W3 возможен опциональный переход на `openrouter/anthropic/claude-haiku-4.5` или DeepSeek-Flash как primary.
- ⚠️ Cloudflare Tunnel как альтернатива Tailscale — для тех у кого уже есть Cloudflare + домен.
- 💡 CrowdSec community blocklist — защита от ботнетов на сетевом уровне.
- 💡 OpenSSH 9.8+ `PerSourcePenalties` — встроенный fail2ban-like.
