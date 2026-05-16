# Стандарт готовности — Воркшоп 3

> Версия: v1.0 (2026-05-13). Матёрый сотрудник — видит мир и действует сам.
> Что должно быть настроено у участника после Воркшопа 3.
> Это **источник истины** — все промпты ссылаются на этот документ.
> AI-исполнитель и аудитор используют его как чек-лист.

---

## Легенда

- ❗ **Критично** — без этого В3 не пройден
- ⚠️ **Рекомендуется** — желательно но не блокер
- 💡 **Опционально** — фича для продвинутых / для В4

---

## ⚠️ Стек моделей В3 — GPT-5 как primary через ChatGPT Plus

В1+В2 ставили primary `minimax/MiniMax-M2.7`. В3 переходим на **`openai/gpt-5`** через подписку ChatGPT Plus ($20/мес) — авторизация через Codex CLI OAuth (это официальный путь OpenAI для агентов).

**Каскад после В3:**
- **Primary:** `openai/gpt-5` (через Codex CLI OAuth, ChatGPT Plus подписка)
- **Fallback:** `minimax/MiniMax-M2.7` (был primary в В1+В2, теперь запасной — рабочий через token-pay)
- **Heartbeat:** `openrouter/google/gemini-2.5-flash-lite` (как было)
- **Subagents/compaction summarizer:** `openrouter/moonshotai/kimi-k2.6` (как было)
- **Premium alias:** `deepseek/deepseek-v4-pro` (как было)
- **Image default:** `openrouter/google/gemini-2.5-flash-image` (как было)
- **Browser-use vision:** `openrouter/google/gemini-2.5-flash-lite` (та же что heartbeat, через OpenRouter, без отдельного Google AI Studio ключа)

Anthropic-моделей в стеке НЕТ напрямую (Max OAuth закрыт с апреля 2026). Если нужен Claude — только через `openrouter/anthropic/...`.

---

## A. OAuth + каскад моделей (GPT-5 primary)

| # | Критерий | Уровень |
|---|---|---|
| A.1 | `npm i -g @openai/codex` установлен под `clawd`: `which codex` → `/home/clawd/.npm-global/bin/codex` | ❗ |
| A.2 | OAuth flow `codex` → "Sign in with ChatGPT" пройден, токен сохранён в `~/.codex/auth.json` (chmod 600) | ❗ |
| A.3 | В `openclaw.json` добавлен auth profile `openai-codex` (использует токен Codex CLI) | ❗ |
| A.4 | `agents.defaults.model.primary` = `openai/gpt-5` | ❗ |
| A.5 | `agents.defaults.model.fallback` = `minimax/MiniMax-M2.7` (старый primary как запасной) | ❗ |
| A.6 | В реальном ответе боту в Telegram модель = `openai/gpt-5` (проверка через `openclaw logs --plain --limit 30`) | ❗ |
| A.7 | `/model` в Telegram показывает `openai/gpt-5` | ⚠️ |

⚠️ **Контекст A:** Codex CLI — официальный продукт OpenAI (`github.com/openai/codex`). OAuth через ChatGPT Plus/Pro/Business/Edu/Enterprise — поддерживаемый OpenAI способ авторизации агентов. Подписка $20/мес даёт доступ к GPT-5 (в ChatGPT auto-switching на GPT-5.4 Thinking при сложных запросах).

---

## B. Веб-инструменты (Brave + Tavily + web_fetch)

| # | Критерий | Уровень |
|---|---|---|
| B.1 | Brave Search API ключ в `~/.openclaw/.env` как `BRAVE_API_KEY` (free 2000/мес) | ❗ |
| B.2 | В `openclaw.json` блок `tools.braveSearch.apiKey` = `${BRAVE_API_KEY}` | ❗ |
| B.3 | `web_search` работает: бот на «что нового в AI» возвращает свежие результаты | ❗ |
| B.4 | `web_fetch` работает: бот на URL возвращает текст страницы (статичной) | ❗ |
| B.5 | Tavily MCP подключён: `openclaw mcp list` показывает `tavily` (free 1000/мес) | ⚠️ |
| B.6 | `TAVILY_API_KEY` в `.env`, не в `openclaw.json` напрямую | ❗ |
| B.7 | В `workspace/AGENTS.md` добавлена секция **«Иерархия веб-инструментов»** (incremental — не перезатирает Memory Search Protocol из В2) | ❗ |

---

## C. Браузерный стек (Patchright + Xvfb + human-behavior)

| # | Критерий | Уровень |
|---|---|---|
| C.1 | `xvfb`, `xdotool`, `python3.12`, `python3.12-venv` установлены на VPS (apt) | ❗ |
| C.2 | Виртуальное окружение `/home/clawd/browser-env` создано, в нём установлены: `browser-use[cli]`, `patchright`, `pyvirtualdisplay`, `playwright-ghost-cursor`, `humanization-playwright` | ❗ |
| C.3 | Chrome установлен через `python3 -m patchright install chrome --with-deps` | ❗ |
| C.4 | **browser-use форкнут с заменой импорта** `from playwright` → `from patchright` (методология максимум-стелс — Patchright патчи работают нативно, не через CDP-мост) | ❗ |
| C.5 | Папка профиля браузера `/home/clawd/.browser-profiles/default` создана (persistent profile — история и cookies сохраняются) | ❗ |
| C.6 | systemd-user unit `~/.config/systemd/user/xvfb.service` создан и активен. Xvfb на дисплее `:99`. `loginctl Linger=yes` уже есть с В1. | ❗ |
| C.7 | В `openclaw.json` блок `mcp.servers.browser-use` зарегистрирован, env содержит `DISPLAY=:99`, `BROWSER_HEADLESS=false`, `BROWSER_PROFILE_DIR=/home/clawd/.browser-profiles/default` | ❗ |
| C.8 | Browser-use vision-модель = `openrouter/google/gemini-2.5-flash-lite` (через OpenRouter, без отдельного Google AI Studio ключа) | ❗ |
| C.9 | `tools.deny` в `openclaw.json` запрещает боту редактировать `openclaw.json`, `credentials/`, `secrets/` | ⚠️ |
| C.10 | DataImpulse residential прокси настроен (env-переменные `PROXY_USER`/`PROXY_PASS`) | 💡 |

⚠️ **Контекст C:** Patchright проходит на 2026.5: CreepJS, Cloudflare, Kasada, Akamai, F5, Datadome, Fingerprint.com, Bet365, Sannysoft, Incolumitas, IPHey, Browserscan, Pixelscan. Camoufox остаётся резервным вариантом для следующих воркшопов — для В3 не входит в core stack.

---

## D. Скиллы (7 named skills + AGENTS.md иерархия)

| # | Критерий | Уровень |
|---|---|---|
| D.1 | Скилл `workspace/skills/web-quick/SKILL.md` — быстрый поиск через Brave (web_search) | ❗ |
| D.2 | Скилл `workspace/skills/page-reader/SKILL.md` — чтение URL через web_fetch | ❗ |
| D.3 | Скилл `workspace/skills/deep-research/SKILL.md` — глубокий ресёрч через Tavily MCP | ⚠️ |
| D.4 | Скилл `workspace/skills/browser-agent/SKILL.md` — действия в браузере через browser-use | ❗ |
| D.5 | Скилл `workspace/skills/mail-handler/SKILL.md` — Gmail через google-workspace MCP | ❗ |
| D.6 | Скилл `workspace/skills/calendar-keeper/SKILL.md` — Google Calendar через google-workspace MCP | ❗ |
| D.7 | Скилл `self-improving-agent` установлен из ClawHub: `openclaw skills install self-improving-agent`. Папка `.learnings/` с LEARNINGS.md/ERRORS.md/FEATURE_REQUESTS.md создана. | ❗ |
| D.8 | В `workspace/AGENTS.md` секция **«Когда какой скилл вызывать»** — правила выбора скилла под задачу (incremental — не перезатирает W2 Memory Search Protocol и W3 Иерархию веб-инструментов) | ❗ |
| D.9 | `openclaw skills list` показывает все 7 скиллов (6 кастомных + self-improving-agent) | ❗ |
| D.10 | Тест выбора скилла: на 6 разных запросов (быстрый факт / URL / ресёрч / клик / почта / календарь) бот вызывает РАЗНЫЕ скиллы — проверка через trajectory.jsonl | ❗ |

---

## E. Google Workspace (Gmail + Calendar OAuth)

| # | Критерий | Уровень |
|---|---|---|
| E.1 | Создана **отдельная** ботовая Gmail (не личная!) — гигиена | ❗ |
| E.2 | Google Cloud Console проект `openclaw-bot` создан | ❗ |
| E.3 | Gmail API и Google Calendar API включены в проекте | ❗ |
| E.4 | OAuth Consent Screen настроен (External, test users включают ботовую почту) | ❗ |
| E.5 | OAuth Client ID типа **Desktop app** создан, `client_secret.json` скачан | ❗ |
| E.6 | `client_secret.json` на VPS в `~/.openclaw/secrets/google-oauth.json` (chmod 600) | ❗ |
| E.7 | `google-workspace-mcp` установлен через `uvx` под clawd | ❗ |
| E.8 | В `openclaw.json` MCP-сервер `google-workspace` зарегистрирован | ❗ |
| E.9 | OAuth flow пройден: refresh token сохранён, бот может читать почту и календарь | ❗ |
| E.10 | Scopes минимум: `gmail.readonly`, `gmail.send`, `calendar.readonly`, `calendar.events.readonly` | ❗ |
| E.11 | Тест Gmail: бот пишет сам себе письмо на ботовую почту через `mail-handler` скилл — приходит | ❗ |
| E.12 | Тест Calendar: бот через `calendar-keeper` отвечает «что в календаре завтра?» с реальными событиями | ❗ |

---

## F. Проактивность (HEARTBEAT.md + 3 cron-задачи через диалог)

| # | Критерий | Уровень |
|---|---|---|
| F.1 | `workspace/HEARTBEAT.md` содержит **6 реальных триггеров** (URGENT в memory/, dedline через 24ч, нет активности 3 дня, день публикации Вт/Чт/Сб, прошло 7 дней без /usage, ничего срочного → `HEARTBEAT_OK`) | ❗ |
| F.2 | HEARTBEAT.md явно **запрещает** в фоне: web_search, web_fetch, browser-use, sessions_spawn — только memory_search и чтение файлов | ❗ |
| F.3 | Cron-задача «утренний брифинг» (`0 8 * * *`) поставлена ботом через диалог. Модель: `gemini-2.5-flash-lite`, isolated session, канал доставки Telegram | ❗ |
| F.4 | Cron-задача «вечерний дайджест» (`0 21 * * *`) поставлена ботом, модель `deepseek-v4-flash`, isolated session | ⚠️ |
| F.5 | Cron-задача «контент-напоминание» (`0 9 * * 2,4,6`) поставлена ботом, isolated session | ⚠️ |
| F.6 | `crontab -l` под clawd показывает все 3 задачи | ❗ |
| F.7 | Утренний брифинг **реально использует Google Calendar MCP** — проверка через trajectory.jsonl: tool_call `calendar.*` есть в брифинге | ❗ |
| F.8 | Брифинг идёт isolated session — не засоряет основной диалог | ❗ |

---

## G. Антидетект (доказательство стелса)

| # | Критерий | Уровень |
|---|---|---|
| G.1 | Бот через browser-agent заходит на `https://abrahamjuliot.github.io/creepjs/` и возвращает скриншот — браузер показан как **«human-like»** (Trust Score высокий, без флагов automation) | ❗ |
| G.2 | Скриншот `https://bot.sannysoft.com/` — все Playwright-маркеры зелёные (webdriver=false, Chrome plugins есть, Permissions API correct) | ❗ |
| G.3 | Скриншот `https://browserscan.net/` — Bot Detection = «Normal», WebRTC consistent с IP | ⚠️ |
| G.4 | Скриншот `https://pixelscan.net/` — Consistency check проходит (timezone/locale/IP согласованы). Палиться **только** datacenter IP (VPS) — это норма без residential proxy | ⚠️ |
| G.5 | Бот выполняет реальную задачу (например `https://openrouter.ai/models` — собрать таблицу цен) и возвращает результат | ❗ |

⚠️ **Контекст G:** без residential прокси VPS-IP видим на pixelscan как datacenter — это нормально и единственная «дыра». Все остальные сигналы (webdriver, headless маркеры, движения мыши, canvas, WebGL, паттерн печати, cookies) — зелёные благодаря стеку Patchright + Xvfb + human-cursor + humanization-playwright + persistent profile.

---

## H. GitHub бэкап обновлён под В3

| # | Критерий | Уровень |
|---|---|---|
| H.1 | Autocommit whitelist расширен: `workspace/skills/**/*.md`, `.learnings/*.md`, `REPORT-W3.md` | ❗ |
| H.2 | После Блока 2 (установка) — есть коммит в `auto/cron` с W3-файлами | ❗ |
| H.3 | После Блока 4 (cron-задачи) — есть milestone-коммит `"W3: setup complete <date>"` | ❗ |
| H.4 | `git log auto/cron --oneline -5` под clawd показывает свежие W3-коммиты | ❗ |
| H.5 | `RECOVERY.md` дополнен W3-разделом: как re-auth Codex CLI, как restart Xvfb, как refresh Google OAuth | ⚠️ |
| H.6 | Permission-watchdog F.5 из W2 v1.1 продолжает работать (cron `*/15 * * * *`) — проверь после установки браузера что openclaw.json остался chmod 600 | ❗ |

---

## Финальный итог

После Воркшопа 3 **минимум** должен быть закрыт каждый ❗ критерий разделов A–H.

**Зачёт В3:** все ❗ закрыты И:
- `/model` в Telegram = `openai/gpt-5` (A.6)
- Бот через browser-agent делает реальную задачу с результатом (G.5)
- Антидетект-проверка на CreepJS + Sannysoft зелёная (G.1, G.2)
- Утренний брифинг реально читает Google Calendar (F.7)
- Все 7 скиллов в `openclaw skills list` (D.9)
- Autocommit whitelist обновлён + есть W3-коммиты в auto/cron (H.1, H.2)

⚠️ — желательно закрыть к Воркшопу 4, не блокирует.
💡 — фичи будущего / для В4-В5 (мульти-агенты, прокси-residential, Camoufox).

---

## Известные ограничения OpenClaw 2026.5.x

Те же что в standards/workshop-2-standard.md плюс:
- `openclaw cron add` команды **не существует** в реальной CLI — cron делается через системный `crontab` под clawd. В В3 бот сам себе ставит cron через `exec` tool — это **новая фишка В3**.
- `clawhub install` команды нет — установка плагинов через `openclaw skills install` или `openclaw plugins install` (для 2026.5+ может требоваться `--dangerously-force-unsafe-install`).
- `--session isolated` для cron-задач — реализуется через флаг `openclaw run-prompt --isolated` (или прямой вызов gateway API с `isolated: true` в payload).

---

## Что ОТСУТСТВУЕТ в В3 (зафиксировано → В4/В5)

- **Camoufox** (резервный браузер для Cloudflare-защищённых сайтов) — В4 опц
- **Мульти-агенты + sessions_spawn fan-out** — В4
- **PostgreSQL CRM + engagement scoring** — В5
- **Notion MCP, GitHub MCP** — В4 опц (для тех у кого есть аккаунты)
- **DataImpulse residential proxy** — В3 опц 💡 (нужно только если работа с гео-блоками)
- **n8n двусторонняя интеграция** — В4
- **Mission Control Dashboard** — В5
