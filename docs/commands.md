# Команды бота в Telegram

> Что можно отправлять боту в чате. Все команды работают только в DM с владельцем (`dmPolicy: allowlist`).
> Источник: PRO-02-hidden-features.md, блок-04-telegram.md, docs.openclaw.ai/tools/slash-commands.

---

## Базовые

| Команда | Что делает |
|---|---|
| `/help` | Список доступных команд (динамически собирается из активных skills и tools) |
| `/status` | Краткий статус: модель, текущий sandbox, активные skills |
| `/reset` | Сбросить контекст текущей сессии (бот «забывает» текущий диалог, но не MEMORY.md) |
| `/new` | Создать новую сессию (аналог /reset, но более жёсткий — пересоздаёт сессию) |
| `/restart` | Перезапросить последний ответ модели заново |
| `/clear` | Стереть переписку в Telegram (только локально, у бота история остаётся) |

---

## Переключение моделей

| Команда | Что делает |
|---|---|
| `/model` | Показать текущую модель |
| `/model premium` | Переключиться на DeepSeek V4-Pro **на 5 сообщений**, потом авто-возврат на primary (см. `premiumGuard` в openclaw.json) |
| `/model think` | DeepSeek V4-Pro в thinking-режиме (reasoning, медленнее но точнее) |
| `/model utility` | DeepSeek V4-Flash — самая дешёвая |
| `/model <slug>` | Любая модель из `auth.profiles` (например `/model openrouter/google/gemini-2.5-flash-lite`) |

---

## Voice / Image / Media

| Команда | Что делает |
|---|---|
| `/voice` | Следующий ответ обязательно голосом (через TTS) |
| `/say <text>` | Озвучить произвольный текст голосом |
| `/sing <text>` | Спеть текст (через ElevenLabs music model, если настроен) |
| `/image <prompt>` | Сгенерировать картинку (`google/gemini-2.5-flash-image` по умолчанию) |
| `/image fast <prompt>` | Использовать `flux-schnell` (в 13x дешевле) |

Голосовые сообщения **во входе** автоматически транскрибируются через Whisper Large v3 Turbo (Groq). Если входящее голосовое — ответ идёт голосом по умолчанию (если короткий < 200 символов).

---

## Скрытые / hidden features (см. PRO-02)

| Команда | Что делает |
|---|---|
| `NO_REPLY` | Бот молчит (не отвечает на это сообщение). Используется для служебных сообщений — например, чтобы триггернуть turn без ответа в чат |
| `/btw <вопрос>` | Параллельный side-вопрос без прерывания основной задачи. Бот отвечает отдельным сообщением, не вмешиваясь в основной поток |
| `/debug show` | Показать runtime-overrides (без рестарта daemon) |
| `/debug set <key>=<value>` | Поменять конфиг в памяти gateway без перезаписи файла. Откат — `/debug reset` |
| `/debug reset` | Сбросить все runtime-overrides |
| `/trace on` / `/trace off` | Включить/выключить session-scoped trace плагинов (без полного `/verbose`) |
| `/verbose on` | Полный вывод raw output, tool calls, prompts |
| `/queue debounce:2s cap:25 drop:summarize` | Настроить очередь сообщений: при флуде старые суммаризируются, не теряются |
| `/trajectory <name>` | Экспорт полной trace turn-а агента в bundle (для дебага). Требует `OPENCLAW_TRAJECTORY` env var |
| `/export-trajectory <name>` | То же, но более явный alias |
| `/steer <инструкция>` | Скорректировать поведение текущего turn-а на лету (например, «дай короче») |

---

## Sessions / sub-agents

| Команда | Что делает |
|---|---|
| `/sessions` | Список активных сессий (main + sub-agents) |
| `/session <id>` | Переключиться на конкретную сессию |
| `/session main` | Вернуться в основную сессию |

См. `sessions_spawn`, `sessions_send` tools в блок-16-мульти-агенты.md.

---

## Memory / контекст

| Команда | Что делает |
|---|---|
| `/memory` | Что бот помнит из MEMORY.md (краткое summary) |
| `/forget <ключ>` | Попросить удалить факт из MEMORY.md |
| `/remember <факт>` | Добавить факт в MEMORY.md (требует подтверждения) |

---

## Cron / heartbeat

| Команда | Что делает |
|---|---|
| `/cron list` | Список запланированных cron-задач |
| `/cron add <description>` | Создать cron-задачу естественным языком (бот сам вычислит cron-выражение) |
| `/cron run <id>` | Запустить cron-задачу прямо сейчас (для тестирования) |
| `/heartbeat now` | Триггернуть heartbeat-проверку немедленно (вместо ожидания тика) |

---

## Безопасность

| Команда | Что делает |
|---|---|
| `/exec ask` | Включить запрос подтверждения для всех `exec` команд |
| `/exec deny` | Запретить exec вообще |
| `/budget` | Показать траты сегодня и за месяц с разбивкой по моделям |
| `/budget set daily=1.5` | Изменить `dailyCapUsd` в runtime |

---

## Что бот понимает текстом (без слешей)

- «Не отвечай на это сообщение» / «нет ответа» → бот молчит (как `NO_REPLY`).
- «Кстати, ...» / «между прочим» → бот может ответить параллельно (как `/btw`).
- «Сложнее, дай премиум» → бот переключается на premium (как `/model premium`).
- «Спой ...» → автоматически использует `/sing`.
- «Нарисуй ...» → автоматически использует `/image`.

---

## Что НЕ работает

- `/install <skill>` — установка skills через Telegram отключена для безопасности. Делай через SSH + `openclaw skills install` или через config.
- `/shell <команда>` — нет такой команды. Exec — через `tools.exec.allowlist` в openclaw.json или через AI-плагин в Antigravity.

---

## Команды, которые **только владелец** может вызвать

В Telegram владелец определяется по `${TELEGRAM_USER_ID}` (числовой ID). Если кто-то другой пишет команду — `/debug`, `/budget`, `/cron add` — бот игнорирует. См. `dmPolicy: "allowlist"`.

---

## Если команда не работает

1. Проверь через `/status` что бот живой.
2. `/help` — может команда переименована.
3. Логи: `ssh clawd-vps 'journalctl --user -u openclaw -g <command-name>'`.
4. Если новая фича — обнови OpenClaw: `ssh clawd-vps 'npm install -g openclaw@latest && systemctl --user restart openclaw'`.
