# skills/

Кастомные OpenClaw skills — автономные модули, которые расширяют возможности бота.

---

## Что такое skill

Skill — это папка с:
- `SKILL.md` — описание (что делает, когда использовать, edge cases).
- `tool.json` (опц.) — описание tool-схемы.
- Код скрипта (Python / Node / bash).
- `assets/` (опц.) — шаблоны, конфиги.

OpenClaw подгружает skill автоматически из `~/.openclaw/workspace/skills/<slug>/` или из глобальной директории.

---

## Структура skill

```
my-skill/
├── SKILL.md              # ОБЯЗАТЕЛЬНО — name, description, when_to_use, examples
├── tool.json             # схема tool (name, description, input_schema)
├── handler.py / .ts      # код
└── README.md             # для разработчика skill
```

---

## Источники готовых skills

- **ClawHub** — https://clawhub.ai (marketplace).
- **GitHub topics:** [openclaw-skill](https://github.com/topics/openclaw-skill).
- **Сообщество:** OpenClaw Discord.

---

## Что НЕ ставить вслепую

По АУДИТу, эти skills **не подтверждены** в публичном индексе ClawHub:
- `google-calendar`, `gmail-integration`, `obsidian-sync`, `qmd-external`, `dashboard-pack`

Для Google Calendar / Gmail / Notion — используй MCP-серверы (`workspace/TOOLS.md`).

---

## Как добавить skill в этот deck

```bash
# 1. Положи папку с skill сюда
cp -r ~/Downloads/some-skill/ skills/some-skill/

# 2. Пропиши в config/openclaw.json
# "skills": {
#   "entries": {
#     "some-skill": {
#       "enabled": true,
#       "path": "~/.openclaw/workspace/skills/some-skill"
#     }
#   }
# }

# 3. Деплой
./scripts/deploy.sh

# 4. Проверка на VPS
ssh clawd-vps 'openclaw skills check'
```

---

## Как написать свой skill

См. блок-08-skills-clawhub.md из ресерча — там полный walkthrough.

Минимум:
1. Создай `skills/my-skill/SKILL.md` с описанием.
2. Добавь `handler.py` или эквивалент.
3. Опиши tool в `tool.json`.
4. Тестируй локально через `openclaw skills run my-skill --input '{"foo":"bar"}'`.

---

## Безопасность

- Skill наследует `tools.profile` бота (по умолчанию `full`).
- Sandbox применяется (`sandbox.mode: non-main` в openclaw.json).
- Перед установкой стороннего skill **прочитай его `SKILL.md`** на предмет внешних запросов / sensitive scopes.
