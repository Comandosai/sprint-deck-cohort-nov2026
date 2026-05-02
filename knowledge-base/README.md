# 🧠 База знаний по OpenClaw

> **2 МБ выверенного материала**: 20 блоков исследований + 5 PRO-материалов + known-issues от реальной 2-дневной отладки.

---

## 🎯 Зачем эта база

База знаний используется двумя способами:

1. **Для AI-агента** в основном чате Antigravity (Claude Code / Codex). При запуске Промпта #0 (meta) AI читает `standards/workshop-1-standard.md` + `knowledge-base/known-issues/`. Это снимает ловушки **до того** как они случатся.

2. **Для AI-консультанта** в новом чате (см. `CONSULTANT-PROMPT.md`). Если что-то непонятно или сломалось — открываешь второй чат AI, вставляешь промпт консультанта, задаёшь вопрос. Консультант ищет ответ в этой базе + при необходимости ходит в интернет.

---

## 📁 Структура

```
knowledge-base/
├── README.md                       ← ты здесь (индекс)
├── CONSULTANT-PROMPT.md            ← промпт для нового чата AI как консультанта
│
├── known-issues/                   ← реальные ловушки и фиксы
│   ├── 01-1008-pairing-required.md       (главная боль)
│   ├── 02-path-non-login-shell.md        (openclaw: command not found)
│   ├── 03-device-pair-disabled.md        (плагин выключен → нет pairing)
│   ├── 04-slug-case-sensitive.md         (MiniMax-M2.7 vs minimax-m2.7)
│   ├── 05-bot-silent-in-telegram.md      (бот думает но молчит)
│   ├── 06-runaway-4200-incident.md       ($4200 за 63 часа)
│   └── 07-env-not-in-systemd.md          (ключи не пробрасываются)
│
├── blocks/                         ← 20 блоков глубокого ресерча
│   ├── блок-01-vps-фундамент.md
│   ├── блок-02-установка-openclaw.md
│   ├── блок-03-llm-провайдеры.md
│   ├── блок-04-telegram.md
│   ├── блок-05-личность.md            (SOUL.md / USER.md / AGENTS.md)
│   ├── блок-06-память.md              (MEMORY.md, hybrid search)
│   ├── блок-07-tools.md               (fs / exec / web / image)
│   ├── блок-08-skills-clawhub.md
│   ├── блок-09-mcp-серверы.md
│   ├── блок-10-obsidian.md
│   ├── блок-11-безопасность.md
│   ├── блок-12-проактивность.md       (HEARTBEAT.md, cron)
│   ├── блок-13-дашборд.md
│   ├── блок-14-git-workflow.md
│   ├── блок-15-mem0-память.md         (Qdrant + embeddings)
│   ├── блок-16-мульти-агенты.md
│   ├── блок-17-n8n.md
│   ├── блок-18-мобильные-ноды.md
│   ├── блок-19-lobster.md             (YAML workflows)
│   └── блок-20-режим-бога.md
│
└── pro/                            ← 5 PRO-материалов (углублённые темы)
    ├── PRO-01-cost-performance.md           (оптимизация цены)
    ├── PRO-02-hidden-features.md            (недокументированные фичи)
    ├── PRO-03-community-wisdom.md           (опыт сообщества)
    ├── PRO-04-production-hardening.md       (production-уровень защиты)
    └── PRO-05-memory-multiagent.md          (память + мульти-агенты)
```

**Размер**: ~2 МБ. **Источники**: docs.openclaw.ai, github.com/openclaw, reddit, X, habr, community-блоги. Дата проверки: апрель-май 2026.

---

## 🆘 Если что-то сломалось — открой `known-issues/`

Реальные проблемы которые мы встретили на установке. Каждый файл:
- 🩺 **Симптом** — что видишь
- 🎯 **Корневая причина** — почему так
- ✅ **Фикс** — точная команда
- 🛡 **Профилактика** — как не повторить

| Файл | Когда открывать |
|---|---|
| **01-1008-pairing-required.md** | Бот молчит, в логах `gateway closed (1008)` |
| **02-path-non-login-shell.md** | `openclaw: command not found` из cron / SSH-batch |
| **03-device-pair-disabled.md** | `paired.json` пустой, `devices list` показывает `No device pairing entries` |
| **04-slug-case-sensitive.md** | Бот отвечает через DeepSeek вместо MiniMax |
| **05-bot-silent-in-telegram.md** | Универсальный гид по «бот молчит» — все 4 причины |
| **06-runaway-4200-incident.md** | Подозрительно большой счёт от провайдера |
| **07-env-not-in-systemd.md** | `MINIMAX_API_KEY: not set` хотя файл есть |

---

## 📚 Если нужна теория — смотри `blocks/` и `pro/`

| Тема | Где смотреть |
|---|---|
| Защита VPS (ufw, fail2ban, swap) | `blocks/блок-01-vps-фундамент.md` |
| Установка daemon | `blocks/блок-02-установка-openclaw.md` |
| Каскад моделей (MiniMax / DeepSeek / OpenRouter) | `blocks/блок-03-llm-провайдеры.md` + `pro/PRO-01-cost-performance.md` |
| Telegram + multi-chat | `blocks/блок-04-telegram.md` |
| SOUL.md / USER.md / AGENTS.md | `blocks/блок-05-личность.md` |
| Память (MEMORY.md + mem0) | `blocks/блок-06-память.md` + `blocks/блок-15-mem0-память.md` + `pro/PRO-05-memory-multiagent.md` |
| Tools (fs / exec / web / image) | `blocks/блок-07-tools.md` |
| Skills из ClawHub | `blocks/блок-08-skills-clawhub.md` |
| MCP-серверы | `blocks/блок-09-mcp-серверы.md` |
| Obsidian-интеграция | `blocks/блок-10-obsidian.md` |
| Безопасность | `blocks/блок-11-безопасность.md` + `pro/PRO-04-production-hardening.md` |
| Проактивность (HEARTBEAT.md) | `blocks/блок-12-проактивность.md` |
| Дашборд / Control UI | `blocks/блок-13-дашборд.md` |
| Git workflow | `blocks/блок-14-git-workflow.md` |
| Мульти-агенты (main / research / content / support) | `blocks/блок-16-мульти-агенты.md` |
| n8n интеграция | `blocks/блок-17-n8n.md` |
| Mobile-ноды OpenClaw Node | `blocks/блок-18-мобильные-ноды.md` |
| Lobster (YAML workflows) | `blocks/блок-19-lobster.md` |
| Режим бога (Smart Routing, Memory Injection, Cognee) | `blocks/блок-20-режим-бога.md` |
| Скрытые фичи | `pro/PRO-02-hidden-features.md` |
| Опыт community | `pro/PRO-03-community-wisdom.md` |

---

## 🎯 Как использовать AI-консультанта

1. Открой **новый чат AI** в Antigravity (или Claude.ai в браузере, или ChatGPT)
2. Скопируй содержимое `CONSULTANT-PROMPT.md`
3. Вставь в чат
4. Задай вопрос: «бот молчит, что делать?»
5. Получишь ответ с цитатой из этой базы знаний за 30 секунд

⚠️ Консультанту нужен доступ к этой папке через файловую систему. Если ты в браузере (Claude.ai / ChatGPT) — придётся скопировать конкретный нужный файл в чат вместе с промптом. В Antigravity AI имеет прямой доступ к knowledge-base/.

---

## 📝 Что НЕ в базе знаний

База — это **справка**, не **инструкция установки**. Для установки используй:

| Если хочешь | Открой |
|---|---|
| Гибридный путь (AI + ручной onboard) | `workshop-1/01-prompts.md` |
| Полностью руками без AI | `workshop-1/01a-install-by-hand.md` |
| Интерактивный гайд в браузере | `workshop-1/guide.html` |
| Самопроверка через сам бот | `workshop-1/02-self-check.md` |
| Независимый аудитор | `workshop-1/03-audit.md` |
| Список критериев готовности (~30) | `standards/workshop-1-standard.md` |

---

## 🆘 Если в базе ответа НЕТ

База покрывает 90% типовых ситуаций. Если твоя проблема не покрыта:

1. Открой консультанта (`CONSULTANT-PROMPT.md`) — он сходит в интернет
2. Спроси в общем чате спринта @ai_comandos
3. Поищи в [GitHub issues OpenClaw](https://github.com/openclaw/openclaw/issues)
4. Поищи в [docs.openclaw.ai](https://docs.openclaw.ai)

И **обязательно** — если нашёл новое решение, напиши Дмитрию (@ai_comandos), чтобы добавить в `known-issues/` для следующих когорт.

---

## 📊 Версия

**База знаний**: v1.0 (5 мая 2026)
**Источник материалов**: спринт-research deep dive 30 апреля 2026 + 2-дневная боль установки 2 мая 2026
**Дата последней актуализации**: 5 мая 2026
