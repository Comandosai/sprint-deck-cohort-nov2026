# AGENTS.md — контекст для AI-плагина

> Этот файл автоматически читают AI-плагины в Antigravity (Claude Code, Codex, Cursor).
> Он описывает что это за проект и как с ним работать. Не путай с `workspace/AGENTS.md` — это файл для **бота на VPS**, а не для AI-плагина в Antigravity.

---

## Что это за проект

**Comandos Claw Deck** — пульт управления удалённым OpenClaw-агентом на VPS.

Бот живёт на VPS и общается с владельцем через Telegram. Эта папка — рабочее место, через которое мы редактируем личность бота, его конфиг, скрипты деплоя и runbooks.

Я (AI-плагин) не выполняю задачи бота напрямую. Я помогаю владельцу управлять ботом через SSH и скрипты в `scripts/`.

---

## Как ты должен работать

### Жёсткие правила

1. **Никогда не коммить** `.env`, `secrets/`, любые ключи. Уже в `.gitignore`.
2. **Перед каждым `./scripts/deploy.sh`** делай `git commit -am "..."` — это snapshot для отката.
3. **Не редактируй файлы на VPS вручную.** Меняй локально (`workspace/`, `config/`), потом deploy.
4. **Для типовых операций** используй скрипты из `scripts/` — не пиши SSH-команды вручную.
5. **Перед сложным изменением конфига** — прочитай соответствующий runbook в `checklists/`.
6. **Если что-то горит** (деньги утекают, бот молчит) — сразу в `checklists/emergency-stop.md` или `docs/troubleshooting.md`.

### Workflow по умолчанию

При запросе владельца:
1. **Прочитай** релевантный файл из `workspace/` или `checklists/`.
2. **Применяй** изменения локально в `workspace/`, `config/`.
3. **Используй** скрипты из `scripts/` для деплоя и проверки.
4. **Отчитайся** что сделано + что проверить.

---

## Структура deck

```
comandos-claw-deck/
├── README.md                  # Что это и как открыть
├── AGENTS.md                  # ← этот файл (контекст для AI-плагина)
├── .env.example               # Шаблон секретов
├── .gitignore                 # Защита от коммита секретов
│
├── workspace/                 # Личность бота — заливается на VPS
│   ├── SOUL.md                # Голос, тон, ценности
│   ├── USER.md                # Профиль владельца
│   ├── AGENTS.md              # SOP для бота (не путать с этим файлом!)
│   ├── TOOLS.md               # SSH, MCP, voice IDs
│   ├── IDENTITY.md            # Имя, эмодзи, аватар
│   ├── HEARTBEAT.md           # Проактивные проверки
│   ├── BOOT.md                # Стартовый ритуал
│   ├── MEMORY.md              # Декларативная долгосрочная память
│   └── memory/                # Daily logs (не коммитить содержимое)
│
├── config/
│   ├── openclaw.json                # Главный конфиг (4 модели, спендинг, voice, image)
│   ├── docker-compose.qdrant.yml    # Qdrant для vector memory
│   └── systemd/openclaw.service     # User-unit для daemon
│
├── checklists/                # Оперативные runbooks
│   ├── deploy-agent.md        # Стандартный deploy
│   ├── gateway-restart.md     # Если gateway завис
│   ├── config-patch.md        # Hot-reload без рестарта
│   ├── disaster-recovery.md   # VPS умер → 30 минут до бота
│   └── emergency-stop.md      # Деньги утекают → стоп за 10 секунд
│
├── scripts/                   # Bash, исполняемые
│   ├── connect.sh             # SSH с туннелями 4000+6333
│   ├── deploy.sh              # rsync workspace → VPS + restart
│   ├── status.sh              # Healthcheck
│   ├── pull.sh                # Sync обратно с VPS (сохраняет правки бота)
│   ├── emergency-stop.sh      # Kill switch
│   └── README.md              # Описание каждого скрипта
│
├── skills/                    # Кастомные OpenClaw skills
│   └── README.md              # Как добавлять
│
└── docs/                      # On-demand справки
    ├── commands.md            # Команды бота в Telegram (/model, /voice, NO_REPLY...)
    ├── troubleshooting.md     # Топ-10 проблем
    └── glossary.md            # 25 терминов с метафорами
```

---

## Архитектура бота

```
[Telegram юзер] ←→ [VPS: OpenClaw daemon] ←→ [4 LLM-провайдера]
                          ↑
                          │ SSH (через scripts/)
                          │
[AI-плагин в Antigravity + этот deck]
```

На VPS:

```
~/.openclaw/
├── openclaw.json            # ← из config/openclaw.json
├── workspace/               # ← из workspace/
│   ├── SOUL.md
│   ├── USER.md
│   └── ...
├── memory/                  # Daily logs (растут на VPS, периодически pull)
├── secrets/                 # chmod 600 — токены провайдеров
└── browser-profiles/        # Chromium cookies для browser tool
```

### Каскад моделей (зафиксирован в `config/openclaw.json`)

| Роль | Модель | Канал | Зачем |
|---|---|---|---|
| **PRIMARY** | `minimax/minimax-m2.7` | MiniMax Coding $10/мес | 90% диалогов |
| **FALLBACK** | `deepseek/deepseek-v4-flash` | DeepSeek API | дёшево, всегда дешевле primary |
| **HEARTBEAT** | `openrouter/google/gemini-2.5-flash-lite` | OpenRouter | 24/7 фон, lightContext |
| **SUBAGENTS** | `openrouter/moonshotai/kimi-k2.6` | OpenRouter | parallelism |
| **PREMIUM** (по `/model premium`) | `deepseek/deepseek-v4-pro` | DeepSeek API | сложные задачи |
| **THINKING** | `deepseek/deepseek-v4-pro:thinking` | DeepSeek API | reasoning |

**Никакого авто-fallback на дорогие модели** — это защита от runaway spending.

---

## Ключи в `.env`

Обязательные (4):
- `MINIMAX_API_KEY` — Coding Plan, platform.minimax.io
- `DEEPSEEK_API_KEY` — api-docs.deepseek.com
- `OPENROUTER_API_KEY` — openrouter.ai (поставь Spending Limit $30/мес!)
- `GROQ_API_KEY` — console.groq.com (Whisper бесплатно)
- `TELEGRAM_BOT_TOKEN` — @BotFather
- `TELEGRAM_USER_ID` — числовой ID через @userinfobot

Опциональные:
- `OPENAI_API_KEY` — TTS (~$1-2/мес)
- `TAVILY_API_KEY` — MCP search
- `VPS_IP`, `VPS_USER` — для скриптов

Без `.env` ничего не работает. Если файла нет — `cp .env.example .env`.

---

## Скрипты, которые ты часто вызываешь

| Скрипт | Что делает |
|---|---|
| `./scripts/connect.sh` | SSH к VPS с проброской портов (4000 → дашборд, 6333 → Qdrant) |
| `./scripts/deploy.sh` | git snapshot → rsync `workspace/` + `config/` → VPS → restart daemon |
| `./scripts/status.sh` | Healthcheck: daemon, gateway, spending, models, RAM, диск |
| `./scripts/pull.sh` | rsync с VPS обратно (бот мог редактировать SOUL.md / memory/) |
| `./scripts/emergency-stop.sh` | `systemctl --user stop openclaw` — стоп за 5 секунд |

---

## Защита от runaway spending (4 уровня)

В `config/openclaw.json` уже зашиты:

1. **Config cap:** `spending.dailyCapUsd: 2`, `monthlyCapUsd: 30`, `killSwitchAt: 5`.
2. **Provider hard limit:** OpenRouter $30/мес (ставится у провайдера).
3. **Watchdog kill-switch:** cron каждые 30 мин проверяет `openclaw spend`.
4. **Heartbeat rate limit:** `1/мин, 5/час, 50/день`.

Если видишь что что-то «горит» — `./scripts/emergency-stop.sh` или `checklists/emergency-stop.md`.

---

## Где смотреть когда что

| Проблема | Файл |
|---|---|
| Бот молчит | `docs/troubleshooting.md` → раздел «Бот молчит» |
| Browser не работает (5 причин) | `docs/troubleshooting.md` → раздел «Browser» |
| Деньги утекают | `checklists/emergency-stop.md` |
| VPS умер | `checklists/disaster-recovery.md` |
| Gateway завис | `checklists/gateway-restart.md` |
| Нужно поправить конфиг без рестарта | `checklists/config-patch.md` |
| Делаю обычный deploy | `checklists/deploy-agent.md` |
| Что значит слово «daemon»? | `docs/glossary.md` |
| Команды бота в Telegram | `docs/commands.md` |

---

## Версия

```
Deck version: 1.0.0
OpenClaw target: 0.9.x (на момент 2026-04)
Owner: Дмитрий Попов (@ai_comandos)
```

Получить обновления: `git pull origin main`.

---

**Помни: ты помогаешь не просто писать код — ты управляешь живым агентом, который тратит реальные деньги и общается с реальными людьми. Перед изменениями думай о последствиях, перед деплоем коммить, перед опасным — спрашивай.**
