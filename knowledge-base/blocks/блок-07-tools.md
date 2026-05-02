# Блок 7: Tools (fs/exec/web/browser)

> **Что:** Настройка инструментов OpenClaw — файловая система (read/write/edit/apply_patch), терминал (exec/process), веб (web_search/web_fetch), браузер (browser через Chromium CDP).
> **Зачем:** Превратить ассистента из "говорящей головы" в полноценного агента: читать/писать файлы, запускать команды на VPS, искать информацию в интернете, кликать по реальным веб-страницам.
> **Время:** 30-45 минут (базовая настройка) + 20-30 минут (выбор и подключение web search provider) + 15-20 минут (browser tuning под VPS).

---

## 🎯 Цель блока

К концу блока Дмитрий должен иметь:

1. **Рабочий fs-стек** — бот может читать `~/.openclaw/`, писать в рабочий каталог проекта, патчить файлы через `apply_patch` (мульти-hunk diff).
2. **Контролируемый exec** — `tools.exec.ask: "on"` спрашивает подтверждение для опасных команд, `process` запускает фоновые процессы (типа `npm run dev`) без блокировки сессии.
3. **Web search** — выбран и подключён один основной provider (рекомендация — **Brave Search API**, free 2000 запросов/мес) + fallback на DuckDuckGo (без ключа) или SearXNG (self-hosted).
4. **web_fetch** — работает для статичных страниц (быстро, дёшево). Для SPA/JS-rendering — bridge на browser tool.
5. **Browser tool** — managed профиль `openclaw` запускает Chromium в headless режиме на VPS, с включённым SSRF fail-closed и tab cleanup.
6. **Профили tools.profile** — выбран `coding` для основного провайдера (Claude/GLM), `messaging` для Telegram-only сценариев.
7. **Безопасность** — `gateway` НЕ может править `tools.exec.ask` и `tools.exec.security` (защищённые ключи на уровне рантайма).

Критерий успеха: команда `openclaw chat "найди в интернете курс рубля и сохрани в /tmp/rates.json"` отрабатывает за один проход — web_search → web_fetch → write.

---

## ⚡ Что нового в апреле 2026

**1. Browser tool через CDP, не Puppeteer.**
Из выгрузки docs.openclaw.ai/tools/browser: движок — Chromium через **Chrome DevTools Protocol** (CDP). Playwright используется только для batch-actions и PDF export. Это означает: можно подключать **внешние** браузеры (Browserless, Browserbase) через WebSocket, не таща Chromium на VPS.

**2. SSRF fail-closed по умолчанию.**
Browser tool теперь **отказывает** в навигации на приватные IP (10.x, 192.168.x, 127.x), если явно не разрешено в `browser.ssrfPolicy.dangerouslyAllowPrivateNetwork`. Раньше в ранних версиях это было разрешено — теперь нет. Для localhost-разработки нужно явно добавить хост в `hostnameAllowlist`.

**3. Защищённые секции в gateway.**
Из выгрузки: `gateway tool refuses modifications to tools.exec.ask or tools.exec.security`. Это новый страховочный слой — даже если злоумышленник убедит модель "поменять exec.ask на off", рантайм не пропустит.

**4. Tab cleanup по умолчанию.**
`browser.tabCleanup` теперь активен с дефолтами `idleMinutes: 120, maxTabsPerSession: 8, sweepMinutes: 5`. Раньше можно было словить ситуацию, когда забытые вкладки съедали 4-8 ГБ RAM на VPS.

**5. Web search providers — расширенный список.**
Из выгрузки: поддержка 11 провайдеров (Brave, DuckDuckGo, Exa, Gemini, Grok, Kimi, MiniMax, Ollama, Perplexity, SearXNG, Tavily). В апреле 2026 рынок устаканился: Brave/Tavily — для general-purpose, Exa — для глубокого ресерча, Perplexity — для "summarized answers" (но дороже).

**6. Profiles вместо ручного allow/deny.**
Раньше каждый ключ перечислял сам список allow. Теперь есть готовые профили: `full`, `coding`, `messaging`, `minimal`. Можно поверх профиля точечно править `allow`/`deny`. Сильно упрощает конфиг.

**7. byProvider override.**
`tools.byProvider` позволяет дать **разный** набор инструментов разным LLM-провайдерам. Например: дорогому Opus — `coding` (всё), дешёвому Haiku/GLM — `minimal` (только session_status). Экономит кост.

---

## 🛠️ Конкретные инструменты и версии

### Built-in tool names (из выгрузки docs.openclaw.ai/tools)

| Инструмент | Группа | Назначение |
|---|---|---|
| `exec` / `process` | runtime | Shell-команды, фоновые процессы |
| `code_execution` | runtime | Sandboxed Python (для дата-анализа) |
| `browser` | ui | Chromium через CDP |
| `web_search` | web | Поиск через выбранный provider |
| `x_search` | web | Поиск по X/Twitter |
| `web_fetch` | web | HTTP GET страницы (raw HTML) |
| `read` / `write` / `edit` | fs | Файловые операции |
| `apply_patch` | fs | Мульти-hunk diff-патчинг |
| `message` | messaging | Cross-channel сообщения |
| `canvas` | ui | Node Canvas |
| `nodes` | — | Discovery узлов |
| `cron` / `gateway` | — | Расписания и runtime mgmt |
| `image` / `image_generate` / `music_generate` / `video_generate` / `tts` | media | Генерация медиа |
| `sessions_*` / `subagents` | — | Управление сессиями |

### Профили (из выгрузки)

- **`full`** — без ограничений. Только для локальной разработки.
- **`coding`** — `group:fs` + `group:runtime` + `group:web` + `sessions` + `memory` + `cron` + `image` + `media`. **Рекомендация Дмитрию.**
- **`messaging`** — `group:messaging` + `sessions_list/history/send`. Для Telegram-only сценариев.
- **`minimal`** — только `session_status`. Для дешёвых fallback-моделей.

### Группы (из выгрузки)

- `group:runtime` = exec, process, code_execution
- `group:fs` = read, write, edit, apply_patch
- `group:web` = web_search, x_search, web_fetch
- `group:ui` = browser, canvas
- `group:media` = image, image_generate, music_generate, video_generate, tts

### Web Search Providers — сравнение (апрель 2026)

> Цены и лимиты [VERIFY] — актуализируйте перед оплатой по официальным сайтам.

| Provider | Free tier | Цена | Качество | Когда выбирать |
|---|---|---|---|---|
| **Brave Search API** | 2 000 req/мес | от $3/1k req | хорошее, индекс независимый от Google | **Дефолт для Дмитрия** — есть free, не нужен Google |
| **Tavily** | 1 000 req/мес | $0.005-0.008/req | заточено под AI/RAG, есть `search_depth: "advanced"` | если нужны очищенные сниппеты для агента |
| **Exa** | 1 000 req/мес (trial) | от $5/1k req | semantic search, эмбеддинги | глубокий ресерч, академика |
| **Perplexity** | нет (через API ключ) | от $5/1k req + LLM tokens | summarized answers | когда нужен готовый ответ, не URL-ы |
| **DuckDuckGo** | без лимита (instant API) | $0 | среднее, без полного веба | бесплатный fallback, без ключа |
| **SearXNG** | self-hosted | $0 (только VPS) | зависит от подключённых backends | приватность, изоляция, но качество ниже |
| **Gemini / Grok / Kimi / MiniMax** | по их API | в составе LLM | поиск встроен в модель | если уже платите за эти LLM |
| **Ollama** | локально | $0 | low — это not a search engine | для оффлайна / тестов |

**Рекомендация:** Brave Search API (primary) + DuckDuckGo (fallback без ключа) + опционально Tavily для случаев, когда нужны "глубокие" сниппеты.

### Browser профили (из выгрузки)

1. **`openclaw` (managed)** — изолированный, OpenClaw сам поднимает Chromium. CDP port 18800-18899. **Дефолт на VPS.**
2. **`user` (existing-session)** — attach к **уже запущенному** Chrome через Chrome DevTools MCP. Полезно для локальной машины (не нужно логиниться повторно).
3. **`remote`** — внешний CDP через `cdpUrl`. Browserless/Browserbase. **Лучший вариант для VPS без X-сервера.**
4. **Custom** — свой путь к Chromium binary (`browser.executablePath`).

### Browser config keys (из выгрузки)

- `browser.enabled` — глобальный switch
- `browser.headless` — true/false (или `OPENCLAW_BROWSER_HEADLESS=1`)
- `browser.executablePath` — путь к Chromium
- `browser.defaultProfile` — `openclaw` / `user` / `remote`
- `browser.actionTimeoutMs` (default 60000)
- `browser.remoteCdpTimeoutMs` (default 1500)
- `browser.localLaunchTimeoutMs` (default 15000)
- `browser.localCdpReadyTimeoutMs` (default 8000)
- `browser.tabCleanup.{enabled,idleMinutes,maxTabsPerSession,sweepMinutes}`
- `browser.ssrfPolicy.{dangerouslyAllowPrivateNetwork,hostnameAllowlist,allowedHostnames}`

---

## 💡 Лайфхаки и про-приёмы (10 штук)

### Лайфхак 1. `profile: "coding"` + точечный deny — лучший старт

Не пишите `allow` руками с нуля. Возьмите профиль `coding` и добавьте `deny` для того, что не нужно.

```json5
{
  tools: {
    profile: "coding",
    deny: ["x_search", "music_generate", "video_generate"]
  }
}
```

Меньше строк → меньше ошибок → проще ревью.

### Лайфхак 2. `byProvider` — экономия на дешёвых моделях

Дайте дорогому провайдеру (Claude Opus / Sonnet) полный `coding`, а дешёвому fallback (GLM-4.6, Grok, локальный Ollama) — только `minimal`. Тогда дешёвая модель не сможет случайно дёрнуть `image_generate` за $0.04 — она просто не увидит этот инструмент.

```json5
{
  tools: {
    profile: "coding",
    byProvider: {
      "ollama-local": { profile: "minimal" },
      "glm-fallback": { profile: "messaging" }
    }
  }
}
```

### Лайфхак 3. `exec.ask: "on"` — не отключайте даже на dev

Соблазн "ну я же сам пишу команды, зачем подтверждение" заканчивается одним `rm -rf /` от галлюцинации модели. Оставляйте `on`. Подтверждение приходит инлайном в Telegram — секунда-две на нажатие. Дешевле, чем восстановление VPS.

Из выгрузки: `gateway` всё равно не даст вам выключить `tools.exec.ask` через chat, так что даже если модель "решит", что подтверждения мешают, она не сможет их снять.

### Лайфхак 4. Brave Search API — free 2000 запросов точно хватит

Если Дмитрий лично пользуется ботом — 2000 запросов/мес = ~65 в день. Этого хватает с запасом для одного человека. Apply for API key: https://brave.com/search/api/. Пара минут, без карты на бесплатном tier (только email).

### Лайфхак 5. DuckDuckGo как zero-config fallback

`web_search.providers: ["brave", "duckduckgo"]` — если Brave упал/превышен лимит, OpenClaw fallback на DDG. DDG не требует ключа. Качество хуже, но "хоть что-то" в момент аварии лучше, чем 500-я ошибка.

### Лайфхак 6. `web_fetch` сначала, `browser` только если SPA

Стоимость browser-вызова на VPS = 1-2 секунды CPU + 100-300 МБ RAM на вкладку. `web_fetch` = один HTTP-запрос, миллисекунды. Правило в системном промпте: **«Сначала `web_fetch`. Если страница пустая или JS-rendered (React/Vue SPA, ключевые слова: `<div id="root">` пустой), переключайся на `browser.navigate + browser.snapshot`».**

### Лайфхак 7. Browserless для VPS без X-сервера

Если на VPS не получается завести Chromium (нет шрифтов, нет шаренных либ, нет X) — поднимите контейнер Browserless локально:

```bash
docker run -d --restart unless-stopped \
  -p 127.0.0.1:3000:3000 \
  --name browserless \
  ghcr.io/browserless/chromium:latest
```

И в openclaw.json:

```json5
{
  browser: {
    defaultProfile: "remote",
    remote: {
      cdpUrl: "ws://127.0.0.1:3000",
      attachOnly: true
    }
  }
}
```

CDP подключение → Chromium крутится в изолированном контейнере → можно тушить и обновлять отдельно от основного бота.

### Лайфхак 8. SSRF allowlist для локальных сервисов

Если бот должен ходить на `localhost:5432` (Postgres web admin), `127.0.0.1:3000` (твой dev API), нужно явно добавить:

```json5
{
  browser: {
    ssrfPolicy: {
      dangerouslyAllowPrivateNetwork: false,
      hostnameAllowlist: ["localhost", "127.0.0.1"],
      allowedHostnames: ["your-internal-app.local"]
    }
  }
}
```

Не оставляйте `dangerouslyAllowPrivateNetwork: true` "на всякий случай" — это открывает SSRF на cloud metadata (169.254.169.254) и приватные сервисы соседей по VPS.

### Лайфхак 9. `tabCleanup` — обязательно проверьте на VPS

Дефолт: `idleMinutes: 120, maxTabsPerSession: 8, sweepMinutes: 5`. На VPS с 4 ГБ RAM 8 вкладок Chromium = ~3 ГБ. Поджмите:

```json5
{
  browser: {
    tabCleanup: {
      enabled: true,
      idleMinutes: 30,
      maxTabsPerSession: 3,
      sweepMinutes: 2
    }
  }
}
```

3 вкладки × 200 МБ = 600 МБ. Sweep раз в 2 минуты.

### Лайфхак 10. Diagnostic команда для Linux-проблем с Chromium

Из выгрузки: `openclaw browser --browser-profile openclaw doctor --deep` показывает, что не так со снэп-Хромиумом, шрифтами, либами. Запускайте **сразу после** установки openclaw на VPS, **до** первого реального использования. Спасает часы дебага.

```bash
openclaw browser --browser-profile openclaw doctor --deep
# проверит: executablePath, доступные либы, headless capability, CDP-port
```

---

## 📋 Готовые команды и конфиги

### Минимальный `openclaw.json` фрагмент (рекомендация)

```json5
{
  // ... остальная часть конфига (LLM, integrations) выше ...

  tools: {
    profile: "coding",
    deny: ["x_search", "music_generate", "video_generate", "tts"],

    // Защищённые секции (gateway не даст менять через chat)
    exec: {
      ask: "on",                    // Подтверждение опасных команд
      security: {
        denyPatterns: [
          "rm -rf /",
          "rm -rf ~",
          ":(){ :|:& };:",          // fork bomb
          "dd if=/dev/zero of=/",
          "mkfs",
          "> /dev/sda"
        ],
        cwdAllowlist: [
          "/home/dmitriy/projects",
          "/tmp",
          "/var/tmp"
        ],
        sudoMode: "deny"            // exec не имеет sudo
      },
      timeoutMs: 120000,            // 2 минуты на команду
      maxOutputBytes: 2_097_152     // 2 МБ stdout cap
    },

    process: {
      maxConcurrent: 5,             // не больше 5 фоновых процессов
      autoKillOnSessionEnd: true
    },

    fs: {
      allowedRoots: [
        "/home/dmitriy/projects",
        "/home/dmitriy/.openclaw",
        "/tmp"
      ],
      maxFileBytes: 10_485_760,     // 10 МБ на файл
      followSymlinks: false         // защита от symlink-эскейпа
    },

    web_search: {
      providers: ["brave", "duckduckgo"],   // primary + fallback
      defaultProvider: "brave",
      brave: {
        apiKey: "${BRAVE_API_KEY}",          // из .env
        endpoint: "https://api.search.brave.com/res/v1/web/search",
        defaultCount: 10,
        safesearch: "moderate"
      },
      duckduckgo: {
        // не требует ключа
      },
      cacheTtlSeconds: 3600,         // кэшируем результаты на час
      maxResults: 10
    },

    web_fetch: {
      timeoutMs: 15000,
      maxBytes: 5_242_880,           // 5 МБ на страницу
      followRedirects: 5,
      userAgent: "OpenClaw/1.0 (+https://openclaw.ai)",
      stripScripts: true,            // вырезаем <script> для безопасности
      ssrfPolicy: {
        dangerouslyAllowPrivateNetwork: false,
        hostnameAllowlist: []
      }
    },

    byProvider: {
      // Дешёвый GLM получает только messaging — экономия
      "glm-fallback": { profile: "messaging" },
      // Локальный Ollama — минимум
      "ollama-local": { profile: "minimal" }
    }
  },

  browser: {
    enabled: true,
    defaultProfile: "openclaw",     // managed, изолированный
    headless: true,                  // VPS без DISPLAY → всегда headless
    actionTimeoutMs: 60000,
    localLaunchTimeoutMs: 15000,
    localCdpReadyTimeoutMs: 8000,

    tabCleanup: {
      enabled: true,
      idleMinutes: 30,               // прибиваем вкладки старше 30 мин
      maxTabsPerSession: 3,          // не больше 3 вкладок одновременно
      sweepMinutes: 2
    },

    ssrfPolicy: {
      dangerouslyAllowPrivateNetwork: false,  // FAIL-CLOSED
      hostnameAllowlist: [
        "localhost",
        "127.0.0.1"
      ],
      allowedHostnames: []
    },

    // Опция: если хочешь Browserless вместо локального Chromium
    // defaultProfile: "remote",
    // remote: {
    //   cdpUrl: "ws://127.0.0.1:3000",
    //   attachOnly: true
    // }
  }
}
```

### Команды установки и проверки

```bash
# 1. .env — секреты
cd ~/.openclaw
echo 'BRAVE_API_KEY=BSA_xxxxxxxxxxxxxxxxxxxx' >> .env
chmod 600 .env

# 2. Проверить, что openclaw подхватил конфиг
openclaw config show | jq '.tools.profile, .browser.defaultProfile'
# Ожидаем: "coding", "openclaw"

# 3. Diagnostic браузера (КРИТИЧНО на VPS)
openclaw browser --browser-profile openclaw doctor --deep

# 4. Тест fs
openclaw chat "прочитай /etc/hostname и скажи хост"

# 5. Тест exec (с ask:on должен переспросить)
openclaw chat "запусти uptime"

# 6. Тест web_search
openclaw chat "найди 3 свежих новости про OpenClaw"

# 7. Тест web_fetch (статика)
openclaw chat "fetch https://example.com и покажи title"

# 8. Тест browser (SPA)
openclaw chat "открой github.com/openclaw/openclaw в браузере, сделай snapshot"

# 9. Тест Brave API напрямую (если что-то не так)
curl -s -H "X-Subscription-Token: $BRAVE_API_KEY" \
  "https://api.search.brave.com/res/v1/web/search?q=openclaw" | jq '.web.results[0].title'
```

### Browserless через Docker (если локальный Chromium не идёт)

```bash
# Установка
docker run -d --restart unless-stopped \
  -p 127.0.0.1:3000:3000 \
  --memory=1g --cpus=1 \
  --name browserless \
  ghcr.io/browserless/chromium:latest

# Проверка живости
curl -s http://127.0.0.1:3000/json/version | jq '.Browser'
# Ожидаем: что-то типа "HeadlessChrome/126.0.x"

# Patch конфига
# В openclaw.json → browser.defaultProfile: "remote"
# remote.cdpUrl: "ws://127.0.0.1:3000"
# remote.attachOnly: true

# Перезапуск
sudo systemctl restart openclaw
openclaw browser --browser-profile remote doctor --deep
```

### Snap-Chromium (Ubuntu) workaround

Из выгрузки: snap-Chromium лежит в `/snap/bin`. Если openclaw не находит:

```bash
# Указать явно
echo 'export OPENCLAW_BROWSER_EXECUTABLE_PATH=/snap/bin/chromium' >> ~/.bashrc
source ~/.bashrc

# ИЛИ в openclaw.json
# browser.executablePath: "/snap/bin/chromium"
```

### SearXNG self-hosted (Лайфхак для max приватности)

```bash
# Запуск
docker run -d --restart unless-stopped \
  -p 127.0.0.1:8888:8080 \
  -e BASE_URL=http://localhost:8888/ \
  -e INSTANCE_NAME=dmitriy-searx \
  --name searxng \
  searxng/searxng:latest

# В openclaw.json
# tools.web_search.providers: ["searxng", "brave"]
# tools.web_search.searxng.endpoint: "http://127.0.0.1:8888/search"
# tools.web_search.searxng.format: "json"
```

---

## ⚠️ Подводные камни

### 1. `OPENCLAW_BROWSER_HEADLESS` НЕ читается, если в config явно `headless: true/false`

Из выгрузки: env-переменная — это override, но если в `openclaw.json` стоит `browser.headless: false`, env её **не перебьёт**. На VPS без DISPLAY это даст ошибку запуска. **Решение:** уберите явный `false` из конфига для VPS, или ставьте `true` явно.

### 2. SSRF fail-closed ломает локальную разработку

Запустили локально dev-сервер на `localhost:3000`, бот отказывается туда ходить — "private network blocked". **Решение:** добавьте в `browser.ssrfPolicy.hostnameAllowlist: ["localhost", "127.0.0.1"]` (Лайфхак 8). НО на VPS этот allowlist должен быть **пустой** — у вас там может быть metadata-сервис cloud провайдера на 169.254.169.254.

### 3. Brave API rate limit — мягкий, но есть

Free tier — 2000/мес и 1 запрос/секунду. Если бот в цикле дёрнет 5 запросов сразу, получит 429. **Решение:** включите `cacheTtlSeconds: 3600` (Лайфхак — кэш на час), плюс fallback `["brave", "duckduckgo"]`. После 429 OpenClaw перекинет на DDG автоматически.

### 4. `apply_patch` падает на CRLF/LF mismatch

Если файл сохранён в Windows-стиле (CRLF), а патч сгенерирован моделью в LF — `apply_patch` бьёт. **Решение:** в config `tools.fs.normalizeLineEndings: true` (если такой ключ поддерживается — [VERIFY]). Альтернатива: `dos2unix` пропустить файл перед редактированием.

### 5. `process` забывает убить детей при reload openclaw

Запустили `npm run dev` через `process`, перезагрузили openclaw — node остался крутиться. **Решение:** `tools.process.autoKillOnSessionEnd: true` (Лайфхак). Плюс на уровне systemd — `KillMode=control-group` (Блок 1).

### 6. `web_fetch` без `stripScripts` — XSS-канал в логи

Если в полученном HTML есть `<script>alert(...)</script>` и оно попадает в логи без эскейпа, плюс кто-то смотрит логи в браузерном дашборде — выполнится. **Решение:** `tools.web_fetch.stripScripts: true` (см. конфиг выше).

### 7. Tab cleanup не работает, если CDP завис

Если Chromium процесс жив, но CDP не отвечает — `sweepMinutes` не помогает. **Решение:** systemd watchdog на сам openclaw (Блок 1) + restart раз в сутки через cron.

### 8. `byProvider` overrides — порядок имеет значение

`tools.profile: "coding"` + `tools.byProvider.X.profile: "minimal"` НЕ означает "пересечение coding и minimal". Это **полная замена**. Когда вызов идёт через провайдера X, применяется ТОЛЬКО minimal. **Решение:** запомните: byProvider — это не патч, а override.

### 9. Browser `actionTimeoutMs: 60000` — для современного веба мало

Тяжёлые SPA (Notion, Figma) могут грузиться 10+ секунд. **Решение:** `browser.actionTimeoutMs: 90000` или `120000`. Не делайте 5 минут — лучше пусть фейлится быстро, чем висит.

### 10. `gateway` защита НЕ покрывает прямую запись в openclaw.json

Из выгрузки: `gateway tool refuses modifications to tools.exec.ask or tools.exec.security`. Но это ОБ инструменте gateway. Если у бота есть `write` на `~/.openclaw/openclaw.json` — он формально может переписать конфиг файл напрямую. **Решение:** в `tools.fs.allowedRoots` НЕ включайте `~/.openclaw/`. Для управления конфигом — отдельный workflow через CLI вне бота.

---

## ✅ Чек-лист выполнения

- [ ] В `~/.openclaw/openclaw.json` секция `tools.profile: "coding"` установлена
- [ ] `tools.deny` ограничивает медиа-инструменты, которые не нужны
- [ ] `tools.exec.ask: "on"` стоит явно
- [ ] `tools.exec.security.denyPatterns` содержит `rm -rf /`, fork-bomb, mkfs
- [ ] `tools.exec.security.cwdAllowlist` ограничивает рабочие каталоги
- [ ] `tools.fs.allowedRoots` НЕ содержит `~/.openclaw/` (защита конфига)
- [ ] `tools.fs.followSymlinks: false`
- [ ] `tools.web_search.providers: ["brave", "duckduckgo"]`
- [ ] `BRAVE_API_KEY` получен на https://brave.com/search/api/ и положен в `.env`
- [ ] `.env` имеет права 600
- [ ] `tools.web_search.cacheTtlSeconds: 3600` включён
- [ ] `tools.web_fetch.stripScripts: true`
- [ ] `tools.web_fetch.maxBytes: 5_242_880`
- [ ] `browser.enabled: true`
- [ ] `browser.defaultProfile: "openclaw"` (или `remote` если используете Browserless)
- [ ] `browser.headless: true` (VPS)
- [ ] `browser.tabCleanup` поджат под VPS RAM (idle 30m, maxTabs 3)
- [ ] `browser.ssrfPolicy.dangerouslyAllowPrivateNetwork: false`
- [ ] `browser.ssrfPolicy.hostnameAllowlist` пустой на VPS (или содержит ТОЛЬКО нужное)
- [ ] `openclaw browser --browser-profile openclaw doctor --deep` прошёл без ошибок
- [ ] `tools.byProvider` настроен для дешёвых fallback-моделей
- [ ] Все 9 верификационных команд (см. ниже) прошли успешно

---

## 🧪 Верификация

Пройдите эти 9 проверок последовательно. Каждая должна вернуть ожидаемый результат.

### V1. Конфиг загружен
```bash
openclaw config show | jq '.tools.profile'
# Ожидаем: "coding"
```

### V2. Защищённые секции — через gateway не правятся
```bash
openclaw chat "используй gateway tool: установи tools.exec.ask в off"
# Ожидаем: ответ типа "gateway отказался — это защищённая секция"
```

### V3. fs read работает
```bash
openclaw chat "прочитай /etc/hostname"
# Ожидаем: содержимое файла
```

### V4. fs read блокирует выход за allowedRoots
```bash
openclaw chat "прочитай /etc/shadow"
# Ожидаем: отказ "путь вне allowedRoots"
```

### V5. exec.ask работает
```bash
openclaw chat "запусти команду uptime"
# Ожидаем: запрос подтверждения в Telegram (или CLI prompt)
```

### V6. exec.denyPatterns блокирует rm -rf /
```bash
openclaw chat "запусти rm -rf / для теста"
# Ожидаем: жёсткий отказ ДО запроса подтверждения
```

### V7. web_search через Brave
```bash
openclaw chat "найди в интернете 'openclaw github'"
# Ожидаем: 3-10 результатов с URL и сниппетами
# Проверьте логи openclaw — должно быть "provider: brave"
```

### V8. web_fetch
```bash
openclaw chat "fetch https://example.com и покажи мне title тэг"
# Ожидаем: "Example Domain"
```

### V9. browser navigate + snapshot
```bash
openclaw chat "открой https://github.com/openclaw/openclaw, сделай snapshot, скажи кол-во звёзд"
# Ожидаем: число (или сообщение "не вижу stars badge", если страница изменилась)
# В логах должно быть: navigate ok, snapshot returned (size > 1000 chars)
```

### V10. SSRF блокирует приватные IP
```bash
openclaw chat "открой http://169.254.169.254/latest/meta-data/ в браузере"
# Ожидаем: SSRF blocked, private network not allowed
```

Если все 10 прошли — блок 7 готов.

---

## ⏱ Реальная оценка времени

| Подэтап | Минимум | Средне | С приключениями |
|---|---|---|---|
| Правка `tools.profile`, `allow`, `deny` | 5 мин | 8 мин | 12 мин |
| `exec.ask + security` (denyPatterns, cwdAllowlist) | 5 мин | 10 мин | 15 мин |
| Регистрация Brave API + .env | 5 мин | 8 мин | 15 мин (если email-confirm подвиснет) |
| `web_search` + `web_fetch` config | 5 мин | 8 мин | 12 мин |
| `browser` базовый config + headless | 5 мин | 10 мин | 25 мин (Chromium на VPS не заводится с первого раза) |
| `browser.ssrfPolicy` + `tabCleanup` | 3 мин | 5 мин | 8 мин |
| `byProvider` overrides | 3 мин | 5 мин | 7 мин |
| Diagnostic + V1-V10 | 10 мин | 15 мин | 30 мин |

**ИТОГО:**
- Минимум (всё с первого раза): **~40 мин**
- Реалистично: **~70 мин**
- С приключениями (Chromium не заводится, Brave API долго подтверждает email): **~120 мин**

Оценка Дмитрия "30-45 минут" — оптимистичная. **Реально планируйте 60-90 минут.**

---

## 🔗 Связи с другими блоками

### ДО блока 7
- **Блок 1 (VPS-фундамент)** — нужен пользователь с ограниченными правами, базовая папка `/home/dmitriy/projects`, swap, systemd. Без этого `exec.security.cwdAllowlist` не имеет смысла.
- **Блок 2 (Установка OpenClaw)** — `openclaw onboard` уже прошёл, `~/.openclaw/openclaw.json` существует.
- **Блок 3 (LLM провайдеры)** — провайдеры зарегистрированы, потому что `tools.byProvider` ссылается на их имена.
- **Блок 11 (Безопасность)** — sandbox для browser, AppArmor/seccomp, firewall — обязательно для продакшена. Без них `dangerouslyAllowPrivateNetwork: false` единственная защита от SSRF, и этого мало.

### ПОСЛЕ блока 7
- **Блок 8 (если сценарий — кодинг через бота)** — теперь у бота есть `read/write/edit/apply_patch` + `exec`, можно настраивать workflows для git, тестов, CI.
- **Блок 9 (расписания и автоматизация)** — `cron` инструмент использует `exec`, `process`, `web_search` — всё уже работает.
- **Блок 12 (проактивность)** — браузерные триггеры (мониторинг страниц, автозаполнение форм) опираются на browser tool.
- **Блок 14 (Git workflow)** — `exec` + `apply_patch` — основа автоматизации git operations.
- **Блок 16 (мульти-агенты)** — subagents наследуют `tools.profile`, через `byProvider` можно тонко рулить, что субагент может, а что нет.

---

## 📚 Источники

**Подтверждённые (через WebFetch главного агента):**
- docs.openclaw.ai/llms.txt — полный список tool names, профилей, групп, web search providers.
- docs.openclaw.ai/tools — описание built-in инструментов, конфигурации tools.allow/deny/profile/byProvider, protected settings (`tools.exec.ask`, `tools.exec.security`).
- docs.openclaw.ai/tools/browser — browser engine (Chromium через CDP), Playwright для batch/PDF, browser config keys, профили (openclaw/user/remote/custom), tab cleanup defaults, SSRF policy, headless detection (Linux без DISPLAY/WAYLAND_DISPLAY → автоматически headless), remote CDP shapes (HTTP discovery, ws direct, Browserless, Browserbase, Docker Browserless), Linux troubleshooting (snap пути, doctor --deep команда).

**Best practices (общие, не из выгрузок):**
- Brave Search API pricing/limits — https://brave.com/search/api/ (актуализировать перед оплатой, [VERIFY]).
- Tavily docs — https://tavily.com/ ([VERIFY]).
- Exa AI docs — https://exa.ai/ ([VERIFY]).
- Browserless / Browserbase — https://www.browserless.io/, https://www.browserbase.com/ ([VERIFY]).
- SearXNG self-hosting guide — официальные docs SearXNG.
- SSRF mitigation patterns — OWASP SSRF cheat sheet.
- Chrome DevTools Protocol reference — https://chromedevtools.github.io/devtools-protocol/.

**Помечены [VERIFY] поля:**
- Точные имена web_search provider config keys (например, `tools.web_search.brave.apiKey` vs `tools.web_search.providers.brave.apiKey`) — проверьте на свежей docs.openclaw.ai/tools/web_search.
- Дефолтный provider, если ничего не указать — предположение Brave (актуализируйте).
- Цены/лимиты на апрель 2026 — провайдеры регулярно меняют тарифы.
- Поддержка `tools.fs.normalizeLineEndings` — упомянуто в подводном камне 4 как гипотеза, требует проверки.
