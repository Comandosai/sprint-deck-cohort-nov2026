# Блок 9: MCP-серверы (внешние сервисы через Model Context Protocol)

> **Что:** Подключение Notion, GitHub, Tavily, Playwright и десятков других сервисов к OpenClaw через стандарт MCP (Model Context Protocol).
> **Зачем:** Превратить ассистента из «болталки» в реального AI-сотрудника, который читает Notion-базы, открывает PR в GitHub, ищет свежую информацию через Tavily и автоматизирует браузер.
> **Время:** 1–1.5 часа на 4 базовых сервера + ещё 30 минут на расширение до 10–15.

---

## 🎯 Цель блока

К концу блока у Дмитрия должно быть:

1. Минимум **4 рабочих MCP-сервера** в OpenClaw: Tavily (поиск), Notion (база знаний), GitHub (код), Playwright (браузер).
2. **API-ключи** хранятся в env-переменных (не в JSON-файле в открытом виде).
3. Команда `openclaw mcp list` показывает все сервера со статусом `connected`.
4. Чёткое понимание разницы:
   - **stdio** — локальные сервера через `uvx`/`npx`,
   - **streamable-http** — удалённые managed-сервера (рекомендуемый для облачных),
   - **SSE/HTTP** — старый legacy-транспорт.
5. OpenClaw сам выставлен как MCP-сервер через `openclaw mcp serve` — это даёт Cursor / Claude Desktop / Cline доступ к диалогам, событиям и разрешениям OpenClaw.
6. Понимание разделения **Skill (Блок 8) vs MCP (Блок 9)**:
   - Skill — нативный для OpenClaw, маркдаун + промпт + bash-инструменты.
   - MCP — внешний стандарт Anthropic, любой сервис на любом языке.

---

## ⚡ Что нового в апреле 2026

| Тренд | Что изменилось | Что делать |
|---|---|---|
| **Streamable-HTTP** стал дефолтом | Anthropic в марте 2026 объявила streamable-http рекомендованным транспортом для удалённых серверов. SSE deprecated (но работает). | Для всех новых cloud-серверов выбирай `"transport":"streamable-http"`. |
| **MCP Registry от Anthropic** | Появился официальный реестр серверов на mcp.anthropic.com — авторизованные, подписанные, с auto-update. | Брать сервера оттуда вместо случайных npm-пакетов. |
| **smithery.ai** — community registry | 2000+ MCP-серверов, можно ставить одной командой `smithery install` | Использовать как «App Store» для MCP. |
| **Block-list interpreter vars** | OpenClaw блокирует `NODE_OPTIONS`, `PYTHONPATH`, `LD_PRELOAD` — даже если MCP-сервер пытается их подсунуть. | Не переживать — атаки через injection заблокированы на уровне CLI. |
| **`openclaw mcp serve` стабилен** | Можно подключить OpenClaw как MCP-сервер к Claude Desktop / Cursor / Cline. | Дмитрий получит доступ к диалогам OpenClaw из любого AI-IDE. |
| **GitHub MCP v2** | Официальный сервер от GitHub (не Anthropic) с поддержкой Issues, PRs, Actions, Discussions. Старый `@modelcontextprotocol/server-github` помечен **deprecated**, npm-имя `@github/github-mcp` **не существует** | Использовать managed remote `https://api.githubcopilot.com/mcp/` (streamable-http) или Docker `ghcr.io/github/github-mcp-server` (stdio). |
| **Notion MCP официальный** | В январе 2026 Notion выпустила официальный MCP `@notionhq/notion-mcp-server` с поддержкой database queries и page-creation. | Не использовать форки — только официальный. |
| **Tavily 2.0 API** | Новая модель `tavily-search-pro` с reasoning. | В env поставить `TAVILY_API_KEY` от платного тарифа ($30/мес). |
| **mcp-server-pulse** | Сервис мониторинга — показывает uptime каждого MCP-сервера. | Для production — обязательно подписаться. |
| **OAuth для MCP** | Streamable-http теперь поддерживает OAuth 2.1 через `Authorization: Bearer` с PKCE. | Notion / Linear / Slack — через OAuth, не через personal token. |

---

## 🛠️ Конкретные инструменты и версии (топ-15 MCP)

### 🔴 ТОП-4 базовых (то, что просил Дмитрий)

#### 1. Tavily MCP — AI-поиск в интернете
- **Пакет:** `tavily-mcp` (через `uvx`) или `@mcptools/mcp-tavily` (через `npx`)
- **Транспорт:** stdio
- **API-ключ:** `TAVILY_API_KEY` (получить на tavily.com, free tier — 1000 запросов/мес)
- **Возможности:** `tavily_search`, `tavily_extract`, `tavily_qna_search`, `tavily_news_search`
- **Когда использовать:** ассистенту нужны свежие новости, факты, исследования.

#### 2. Notion MCP — база знаний
- **Пакет:** `@notionhq/notion-mcp-server` (официальный, npm)
- **Транспорт:** stdio (локально) или streamable-http (для команды)
- **API-ключ:** `NOTION_API_KEY` (Internal Integration Token из Settings → Integrations)
- **Возможности:** `notion_search`, `notion_query_database`, `notion_create_page`, `notion_update_page`, `notion_get_block_children`
- **Что важно:** в Notion нужно явно «поделиться» страницами с интеграцией, иначе ассистент их не увидит.

#### 3. GitHub MCP — код и задачи
- **Официальные варианты:**
  - **Managed remote** (рекомендуется): URL `https://api.githubcopilot.com/mcp/`, transport `streamable-http`, авторизация через `Authorization: Bearer ${GITHUB_PAT}`. Не требует локальной установки.
  - **Docker stdio:** образ `ghcr.io/github/github-mcp-server` — для on-prem / приватных сетей.
- **НЕ ИСПОЛЬЗОВАТЬ:** `@modelcontextprotocol/server-github` (deprecated) и `@github/github-mcp` (такого npm-пакета не существует).
- **Транспорт:** streamable-http (managed) или stdio (через docker)
- **API-ключ:** `GITHUB_PERSONAL_ACCESS_TOKEN` (Classic PAT со scope `repo`, `read:org`, `workflow`)
- **Возможности:** read/write Issues, PRs, Actions, Code Search, репозитории
- **Конкретный пример конфига (managed):**
```json
"github-managed": {
  "url": "https://api.githubcopilot.com/mcp/",
  "transport": "streamable-http",
  "headers": { "Authorization": "Bearer ${GITHUB_PAT}" }
}
```
- **Альтернатива (Docker stdio):**
```json
"github-docker": {
  "command": "docker",
  "args": ["run","-i","--rm","-e","GITHUB_PERSONAL_ACCESS_TOKEN","ghcr.io/github/github-mcp-server"],
  "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PAT}" }
}
```

#### 4. Playwright MCP — браузер-автоматизация
- **Пакет:** `@playwright/mcp` (официальный от Microsoft, опубликован под scope `@playwright` на npm)
- **Команда запуска:** `npx -y @playwright/mcp` (или `npx @playwright/mcp@latest`)
- **Репозиторий:** github.com/microsoft/playwright-mcp
- **Транспорт:** stdio
- **API-ключ:** не нужен
- **Зависимости:** `npx playwright install chromium` после первого запуска
- **Возможности:** `browser_navigate`, `browser_click`, `browser_screenshot`, `browser_pdf`, `browser_network_log`
- **Когда использовать:** заполнить форму на сайте, скрапинг, сделать скриншот для отчёта.
- **ВАЖНО:** старое имя `@microsoft/mcp-server-playwright` НЕ существует в npm — это типичная путаница. Канонический slug — `@playwright/mcp`.

---

### 🟡 ТОП-11 расширения (must-have для AI-сотрудника)

| # | MCP-сервер | Команда установки | env-переменные | Зачем |
|---|---|---|---|---|
| 5 | **Filesystem** | `npx -y @modelcontextprotocol/server-filesystem /home/dmitriy/projects` | — | Чтение/запись файлов в указанной директории. |
| 6 | **Memory (knowledge graph)** | `npx -y @modelcontextprotocol/server-memory` | — | Долгосрочная память на graph-структуре (см. также Блок 15 mem0). |
| 7 | **PostgreSQL** | `uvx mcp-server-postgres` | `POSTGRES_CONNECTION_STRING` | Прямые SQL-запросы к продакшн-БД. |
| 8 | **Slack** | `npx -y @modelcontextprotocol/server-slack` | `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID` | Чтение каналов, отправка сообщений. |
| 9 | **Linear** | `uvx mcp-server-linear` | `LINEAR_API_KEY` | Управление задачами Linear. |
| 10 | **Sentry** | `uvx mcp-server-sentry` | `SENTRY_AUTH_TOKEN`, `SENTRY_ORG` | Чтение ошибок продакшна. |
| 11 | **Sequential-thinking** | `npx -y @modelcontextprotocol/server-sequential-thinking` | — | Структурированное многошаговое рассуждение. |
| 12 | **Fetch** | `uvx mcp-server-fetch` | — | HTTP-запросы к произвольным URL (легче, чем Playwright). |
| 13 | **Brave Search** | `npx -y @modelcontextprotocol/server-brave-search` | `BRAVE_API_KEY` | Альтернативный поиск с фокусом на приватность. |
| 14 | **Google Drive** | `npx -y @modelcontextprotocol/server-gdrive` | OAuth | Чтение Docs / Sheets. |
| 15 | **time / weather / fetch-rss** | `uvx mcp-server-time` и т.п. | — | Мелкие утилиты — текущее время, погода, RSS-фиды. |

**Где искать ещё:**
- **github.com/modelcontextprotocol/servers** — официальный монорепозиторий.
- **smithery.ai** — community registry с 2000+ серверов.
- **mcp-servers.com** — каталог с фильтрами.
- **mcp.anthropic.com/registry** — официальный реестр Anthropic (с подписями).

---

## 💡 Лайфхаки и про-приёмы

### 1. **Не пиши API-ключи в openclaw.json — используй `${ENV_VAR}` подстановку**

```json
{
  "mcp": {
    "servers": {
      "notion": {
        "command": "npx",
        "args": ["-y", "@notionhq/notion-mcp-server"],
        "env": {
          "NOTION_API_KEY": "${NOTION_API_KEY}"
        }
      }
    }
  }
}
```

В `~/.openclaw/.env` (с правами 600):
```bash
NOTION_API_KEY=secret_xxxxx
GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxxxx
TAVILY_API_KEY=tvly-xxxxx
```

OpenClaw сам подставляет переменные при старте сервера. Если у тебя `git`-репозиторий с конфигом — никогда не закоммитишь секрет.

### 2. **Streamable-HTTP > stdio для удалённых сервисов**

Если у Notion / GitHub / Linear есть managed MCP-endpoint — используй его. Это:
- быстрее (нет cold-start от `npx`/`uvx`),
- надёжнее (Anthropic / GitHub поддерживают uptime),
- безопаснее (OAuth + scoped tokens).

```bash
openclaw mcp set github-managed '{
  "url": "https://api.githubcopilot.com/mcp/",
  "transport": "streamable-http",
  "headers": { "Authorization": "Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" }
}'
```

### 3. **Локальный stdio для тех, у кого важна приватность**

Postgres / Filesystem / Memory — никогда не должны идти через cloud. Только stdio с локальным процессом. Это правило безопасности №1.

### 4. **`uvx` лучше `npx` для Python-серверов**

`uvx` (от Astral, авторов `uv`) кеширует пакеты, стартует за ~200ms. `npx` каждый раз скачивает зависимости (если не указать `-y`). Для Python-MCP всегда выбирай `uvx`.

```bash
# Хорошо
openclaw mcp set tavily '{"command":"uvx","args":["tavily-mcp"]}'

# Плохо (тоже работает, но медленнее)
openclaw mcp set tavily '{"command":"pip","args":["install","tavily-mcp","&&","tavily-mcp"]}'
```

### 5. **Тест MCP-сервера ДО подключения через `mcp-inspector`**

```bash
npx @modelcontextprotocol/inspector uvx tavily-mcp
```

Откроется веб-интерфейс на localhost:5173. Можно вручную вызывать tools, видеть ответы. Если в инспекторе работает — в OpenClaw тоже сработает.

### 6. **`openclaw mcp show <name>` — debug при «server not connected»**

```bash
openclaw mcp show notion --json
```

Покажет:
- статус (`connected`, `error`, `starting`),
- список tools (если подключен),
- последние 10 строк stderr,
- env-переменные (с замаскированными секретами).

### 7. **`claude-channel-mode` — что это**

`openclaw mcp serve --claude-channel-mode auto|on|off` управляет, отправлять ли все output обратно через специальный `claude` канал MCP (для Claude Desktop). По умолчанию `auto`. Если у тебя Cursor — поставь `off`, чтобы избежать дублирования.

### 8. **Не подключай 30 серверов сразу — выбирай по контексту**

Каждый MCP-сервер = +N tools в системном промпте. С 30 серверами получишь 200+ tools — Claude начнёт путаться, контекст раздуется. Правило: **5–8 активных серверов одновременно**, остальные — выключай через `openclaw mcp unset` или ставь enabled:false.

### 9. **OAuth 2.1 + PKCE для production**

Notion / Slack / Google Drive поддерживают OAuth через MCP Streamable-HTTP. Это намного безопаснее personal-token: scoped доступ, истекающие токены, можно отозвать в один клик. Настройка через `openclaw mcp set` с указанием OAuth callback (см. документацию каждого сервиса).

### 10. **`openclaw mcp serve` = OpenClaw как сервер для Claude Desktop / Cursor**

```bash
# Запускает OpenClaw как MCP-сервер на localhost:18789
openclaw mcp serve --url wss://localhost:18789 --token-file ~/.openclaw/gateway.token
```

Дальше в `~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "openclaw": {
      "url": "wss://localhost:18789",
      "transport": "streamable-http",
      "headers": { "Authorization": "Bearer $(cat ~/.openclaw/gateway.token)" }
    }
  }
}
```

Теперь Claude Desktop может читать диалоги OpenClaw, отправлять сообщения, отвечать на запросы разрешений (`permissions_respond`).

### 11. **Skills (Блок 8) vs MCP — когда что**

| Критерий | Skill | MCP |
|---|---|---|
| Где живёт | `~/.openclaw/skills/` | внешний процесс |
| Язык | Markdown + bash | любой (TS, Python, Go) |
| Стандарт | Внутренний OpenClaw | Открытый стандарт Anthropic |
| Когда брать | Свой воркфлоу, маленький инструмент | Интеграция с внешним сервисом |
| Пример | «Транскрипция видео через ffmpeg» | «Чтение Notion-базы» |

**Правило:** если есть готовый MCP — бери его. Если нет — пиши свой Skill.

### 12. **Безопасность: NODE_OPTIONS / PYTHONPATH блокируются автоматически**

В документации явно сказано: stdio-сервер не может задать `NODE_OPTIONS`, `PYTHONPATH`, `LD_PRELOAD`. Это interpreter-control vars — через них можно подгрузить злой код. OpenClaw проверяет env при старте и роняет процесс, если такие переменные присутствуют.

---

## 📋 Готовые команды и конфиги

### 4 базовых сервера (то, что просил Дмитрий)

```bash
# Tavily — поиск
openclaw mcp set tavily '{
  "command": "uvx",
  "args": ["tavily-mcp"],
  "env": { "TAVILY_API_KEY": "${TAVILY_API_KEY}" }
}'

# Notion
openclaw mcp set notion '{
  "command": "npx",
  "args": ["-y", "@notionhq/notion-mcp-server"],
  "env": { "NOTION_API_KEY": "${NOTION_API_KEY}" }
}'

# GitHub (managed через streamable-http — рекомендуется)
openclaw mcp set github '{
  "url": "https://api.githubcopilot.com/mcp/",
  "transport": "streamable-http",
  "headers": { "Authorization": "Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" }
}'

# Playwright (официальный пакет от Microsoft — @playwright/mcp)
openclaw mcp set playwright '{
  "command": "npx",
  "args": ["-y", "@playwright/mcp"]
}'
```

### Расширение до 14 серверов (полный конфиг)

`~/.openclaw/openclaw.json`:

```json
{
  "mcp": {
    "servers": {
      "tavily": {
        "command": "uvx",
        "args": ["tavily-mcp"],
        "env": { "TAVILY_API_KEY": "${TAVILY_API_KEY}" }
      },
      "notion": {
        "command": "npx",
        "args": ["-y", "@notionhq/notion-mcp-server"],
        "env": { "NOTION_API_KEY": "${NOTION_API_KEY}" }
      },
      "github": {
        "url": "https://api.githubcopilot.com/mcp/",
        "transport": "streamable-http",
        "headers": { "Authorization": "Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" }
      },
      "playwright": {
        "command": "npx",
        "args": ["-y", "@playwright/mcp"]
      },
      "filesystem": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/dmitriy/projects"]
      },
      "memory": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-memory"],
        "env": { "MEMORY_FILE_PATH": "/home/dmitriy/.openclaw/memory.json" }
      },
      "postgres": {
        "command": "uvx",
        "args": ["mcp-server-postgres"],
        "env": { "POSTGRES_CONNECTION_STRING": "${POSTGRES_URL}" }
      },
      "slack": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-slack"],
        "env": {
          "SLACK_BOT_TOKEN": "${SLACK_BOT_TOKEN}",
          "SLACK_TEAM_ID": "${SLACK_TEAM_ID}"
        }
      },
      "linear": {
        "command": "uvx",
        "args": ["mcp-server-linear"],
        "env": { "LINEAR_API_KEY": "${LINEAR_API_KEY}" }
      },
      "sentry": {
        "command": "uvx",
        "args": ["mcp-server-sentry"],
        "env": {
          "SENTRY_AUTH_TOKEN": "${SENTRY_AUTH_TOKEN}",
          "SENTRY_ORG": "comandos-ai"
        }
      },
      "sequential-thinking": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
      },
      "fetch": {
        "command": "uvx",
        "args": ["mcp-server-fetch"]
      },
      "brave-search": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-brave-search"],
        "env": { "BRAVE_API_KEY": "${BRAVE_API_KEY}" }
      },
      "time": {
        "command": "uvx",
        "args": ["mcp-server-time", "--local-timezone=Europe/Moscow"]
      }
    }
  }
}
```

### `.env` файл (chmod 600)

```bash
# ~/.openclaw/.env
TAVILY_API_KEY=tvly-prod-xxxxxxxxxxxxxxxxxx
NOTION_API_KEY=secret_xxxxxxxxxxxxxxxxxx
GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxxxxxxxxxxxxxxxxx
POSTGRES_URL=postgresql://user:pass@host:5432/db
SLACK_BOT_TOKEN=xoxb-xxxx-xxxx-xxxx
SLACK_TEAM_ID=T01234567
LINEAR_API_KEY=lin_api_xxxxxxxxxxxxxxxxxx
SENTRY_AUTH_TOKEN=xxxxxxxxxxxxxxxxxx
BRAVE_API_KEY=BSAxxxxxxxxxxxxxxxxxx
```

```bash
chmod 600 ~/.openclaw/.env
```

### Как сделать OpenClaw сам MCP-сервером (для Claude Desktop / Cursor)

```bash
# Стартуем OpenClaw как сервер
openclaw mcp serve \
  --url wss://localhost:18789 \
  --token-file ~/.openclaw/gateway.token \
  --claude-channel-mode auto \
  -v

# В фоне через systemd / launchd
```

В `~/Library/Application Support/Claude/claude_desktop_config.json` (для Mac):

```json
{
  "mcpServers": {
    "openclaw": {
      "url": "wss://localhost:18789",
      "transport": "streamable-http",
      "headers": {
        "Authorization": "Bearer ВСТАВИТЬ_СОДЕРЖИМОЕ_~/.openclaw/gateway.token"
      }
    }
  }
}
```

Теперь в Claude Desktop появятся tools: `conversations_list`, `messages_send`, `events_wait`, `permissions_respond` и т.д.

---

## ⚠️ Подводные камни

### 1. **Notion: интеграция не видит страницы**
Notion работает по принципу «share, чтобы дать доступ». После создания Internal Integration в Notion → Settings → Integrations нужно зайти в каждую базу/страницу и нажать «Share → Invite → выбрать твою интеграцию». Иначе MCP вернёт пустые результаты.

### 2. **GitHub PAT с истечением**
Classic PAT истекают через 90 дней (если не выбрал «No expiration»). Если ассистент вдруг перестал отвечать на «открой PR в репо X» — проверь PAT на github.com/settings/tokens.

### 3. **Playwright: `npx playwright install chromium` обязателен**
После первой установки `@playwright/mcp` нужно один раз вручную выполнить:
```bash
npx playwright install chromium
```
Иначе сервер падает с `Browser not found`.

### 4. **`uvx` ставится через `pip install uv`**
Если нет `uvx` — установи через:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```
Иначе все Python-MCP не запустятся.

### 5. **stdio-сервер с `cwd` — частая ошибка**
Если сервер требует `cwd: "/path"`, а директории не существует — процесс молча падает. `openclaw mcp show <name>` покажет stderr, но новички часто этого не видят.

### 6. **Слишком много серверов = деградация Claude**
30 серверов × 7 tools = 210 tools в системном промпте. Это съедает 15-20K токенов ДО первого сообщения. Claude начинает путаться, выбирает не те tools. **Правило: 5–8 активных, остальные выключай.**

### 7. **streamable-http без `Authorization` — 401**
Если забыл `headers: { Authorization: "Bearer ..." }` для GitHub managed-MCP — сервер вернёт 401 и в `mcp list` будет статус `auth_failed`.

### 8. **NODE_OPTIONS/PYTHONPATH в env — сервер не стартует**
Если случайно скопировал из StackOverflow конфиг с `"NODE_OPTIONS": "--max-old-space-size=8192"` — OpenClaw откажется стартовать сервер. Это защита от инжекта. Используй обходной путь: запиши настройки в shell-скрипт и вызывай его из `command`.

### 9. **`mcp set` с одинарными кавычками — экранирование**
Если в JSON есть `'`, нужно экранировать через `'\''` или использовать heredoc:
```bash
openclaw mcp set name "$(cat <<'EOF'
{"command":"uvx","args":["..."]}
EOF
)"
```

### 10. **`openclaw mcp serve` НЕ для production без TLS**
Стартует на `wss://` (TLS), но если используешь `ws://` без шифрования — токен утекает в plaintext. В production: `wss://` + валидный сертификат.

---

## ✅ Чек-лист выполнения

- [ ] Установлен `uvx` (`curl -LsSf https://astral.sh/uv/install.sh | sh`)
- [ ] Создан `~/.openclaw/.env` с API-ключами (`chmod 600`)
- [ ] Получены API-ключи: Tavily, Notion (Internal Integration), GitHub PAT (`repo`, `workflow`), Brave (опционально)
- [ ] В Notion: интеграция «приглашена» во все нужные базы
- [ ] Запущен `openclaw mcp set tavily ...` — статус `connected`
- [ ] Запущен `openclaw mcp set notion ...` — статус `connected`
- [ ] Запущен `openclaw mcp set github ...` (managed) — статус `connected`
- [ ] Запущен `openclaw mcp set playwright ...` (с пакетом `@playwright/mcp`) + `npx playwright install chromium`
- [ ] Команда `openclaw mcp list` показывает все 4 сервера со статусом `connected`
- [ ] Тестовый запрос: «найди через tavily последние новости про OpenAI» — ассистент использует `tavily_search`
- [ ] Тестовый запрос: «прочитай мою главную базу в Notion» — ассистент использует `notion_query_database`
- [ ] Тестовый запрос: «открой issue в моём GitHub-репо» — ассистент использует GitHub-инструменты
- [ ] (опционально) Расширение до 14 серверов из конфига выше
- [ ] (опционально) `openclaw mcp serve` подключён к Claude Desktop / Cursor
- [ ] Конфиг закоммичен в git, `.env` в `.gitignore`

---

## 🧪 Верификация

### 1. `openclaw mcp list` — общий обзор
```bash
$ openclaw mcp list

NAME                STATUS      TRANSPORT          TOOLS
tavily              connected   stdio              4
notion              connected   stdio              7
github              connected   streamable-http    23
playwright          connected   stdio              12
filesystem          connected   stdio              5
memory              connected   stdio              9
```

### 2. `openclaw mcp show notion --json` — детали
```json
{
  "name": "notion",
  "status": "connected",
  "transport": "stdio",
  "command": "npx",
  "args": ["-y", "@notionhq/notion-mcp-server"],
  "env": { "NOTION_API_KEY": "***" },
  "tools": [
    "notion_search",
    "notion_query_database",
    "notion_create_page",
    "notion_update_page",
    "notion_get_block_children",
    "notion_append_block_children",
    "notion_retrieve_page"
  ],
  "uptime_sec": 1234
}
```

### 3. Тестовые prompts (отправь ассистенту в Telegram / CLI)

```
Найди через Tavily 3 последние новости про MCP-стандарт за апрель 2026
```
Ожидание: ассистент вызывает `tavily.tavily_search` с query про MCP.

```
Открой мою Notion-базу "Проекты 2026" и покажи 5 последних задач со статусом "В работе"
```
Ожидание: вызов `notion.notion_query_database` с фильтром.

```
Создай issue в репозитории dmitriypopov/openclaw-test с заголовком "Test MCP integration"
```
Ожидание: вызов GitHub MCP `create_issue`.

```
Открой https://example.com через Playwright и сделай скриншот
```
Ожидание: вызовы `playwright.browser_navigate` + `playwright.browser_screenshot`, файл сохраняется локально.

### 4. mcp-inspector для дебага
```bash
npx @modelcontextprotocol/inspector uvx tavily-mcp
# Открыть http://localhost:5173, вручную вызвать tavily_search с query="test"
```

---

## ⏱ Реальная оценка времени

| Этап | Время | Заметки |
|---|---|---|
| Установка `uvx`, создание `.env` | 10 мин | Один раз. |
| Получение API-ключей (Tavily, Notion, GitHub) | 20 мин | Регистрации и нажатия в UI. |
| Настройка 4 базовых серверов через `mcp set` | 10 мин | Копипаст из конфига выше. |
| Проверка `mcp list` + дебаг ошибок | 15 мин | Обычно 1–2 сервера падают на первом старте. |
| Notion: «расшарить» базы с интеграцией | 10 мин | Кликать в UI Notion. |
| Тестовые prompts | 15 мин | Убедиться, что tools реально вызываются. |
| **Итого базовый минимум** | **80 мин** | ≈ 1ч 20м. |
| Расширение до 14 серверов | +30 мин | Если есть Slack / Linear / Sentry аккаунты. |
| `openclaw mcp serve` для Claude Desktop | +20 мин | Опционально. |

**Реалистичная оценка: 1.5 часа на базовое + 1 час на расширение.**

---

## 🔗 Связи с другими блоками

**ДО (что должно быть готово):**
- **Блок 7 (CLI и базовая настройка)** — нужны команды `openclaw mcp set/list/show`.
- **Блок 11 (Безопасность)** — `.env` с правами 600, секреты не в git.

**ПОСЛЕ (что становится возможным):**
- **Блок 8 (Skills)** — сравнение Skill vs MCP, выбор инструмента.
- **Блок 12 (Проактивность)** — ассистент сам мониторит GitHub Issues / Notion базы.
- **Блок 13 (Дашборд)** — статус MCP-серверов выводится на дашборде.
- **Блок 14 (Git workflow)** — GitHub MCP — основной инструмент для PR/Issues.
- **Блок 15 (mem0-память)** — Memory MCP как альтернатива/дополнение.
- **Блок 16 (Мульти-агенты)** — каждый агент может иметь свой набор MCP.
- **Блок 19 (Lobster)** — отдельные MCP для Lobster-сервисов.
- **Блок 20 (Режим бога)** — все MCP включены сразу + расширенные права.

---

## 📚 Источники

- **Официальная документация OpenClaw:** docs.openclaw.ai/cli/mcp
- **Model Context Protocol spec:** modelcontextprotocol.io
- **Anthropic MCP Registry:** mcp.anthropic.com/registry
- **GitHub monorepo с серверами:** github.com/modelcontextprotocol/servers
- **smithery.ai** — community registry MCP
- **mcp-servers.com** — каталог с фильтрами
- **mcp-server-pulse** — мониторинг uptime MCP-серверов
- **Tavily docs:** docs.tavily.com
- **Notion MCP:** github.com/makenotion/notion-mcp-server
- **GitHub MCP:** github.com/github/github-mcp-server
- **Microsoft Playwright MCP:** github.com/microsoft/playwright-mcp
- **uv (для uvx):** astral.sh/uv

---

> **Финальный совет:** не подключай 30 серверов сразу — это раздувает контекст и Claude путается. Старт с 4–6, расширяй по мере реальных задач. Каждые 2 недели делай ревью: какие MCP не используются → отключай через `openclaw mcp unset`.
