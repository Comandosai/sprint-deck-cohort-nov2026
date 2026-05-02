# Блок 8: Skills и ClawHub

> **Что:** Подключение готовых модульных навыков (skills) для типовых задач — календарь, почта, заметки, внешние API — через нативный механизм OpenClaw и публичный реестр ClawHub. Альтернативные пути через MCP-серверы там, где скилла нет.
> **Зачем:** Чтобы не писать с нуля «найди письмо → поставь встречу». Skills — это переиспользуемые, версионируемые, обновляемые модули с собственным конфигом, секретами и precedence-логикой. ClawHub — площадка, где их искать.
> **Время:** 2.5–4 часа на минимальный набор + OAuth Google + первые тесты. Полная докрутка с self-authored skill — +1 день.

---

## 🎯 Цель блока

К концу блока у Дмитрия должно быть:

1. **Установленный набор скиллов** через `openclaw skills install <slug>` либо подключённые альтернативы через MCP, если нативного скилла нет.
2. **Корректно сконфигурированный** `~/.openclaw/openclaw.json` с разделом `skills.entries`, в котором каждый скилл имеет осмысленный `apiKey.source` (env / file / ConfigSecret), а не «вписан plaintext».
3. **OAuth-флоу для Google** (Calendar + Gmail), где `refresh_token` хранится в файле с правами 0600 либо в ОС-keychain — ни в коем случае не в JSON-конфиге plaintext.
4. **Понимание skill precedence**: Workspace → Project → Personal → Managed/Local → Bundled → Extra. Это критично, потому что один и тот же `image-lab` в проекте и в personal даёт два разных поведения.
5. **Тест проходит**: запрос «Найди письмо от Иванова и поставь встречу на вторник 14:00» приводит к реальному действию, а не «I cannot access your email».
6. **Чёткая граница Skill vs MCP**: когда ставить skill, когда ходить через MCP-сервер, когда писать свой плагин.

> **🔴 КРИТИЧЕСКОЕ ПРЕДУПРЕЖДЕНИЕ (подтверждено аудитом 30.04.2026):**
> Скиллы `google-calendar`, `gmail-integration`, `obsidian-sync`, `qmd-external` **в ClawHub НЕ существуют** — индекс при поиске пустой. Никаких `openclaw skills install google-calendar` вслепую — в лучшем случае получите 404, в худшем сквоттер опубликует malware с этим slug. Сразу идите по fallback-маршруту через MCP-серверы (см. ниже и Блок 9).
>
> **Fallback-маршрут (рабочие реальные альтернативы):**
> - **`google-calendar`** → Google Calendar MCP server (`npx -y @smithery/google-calendar-mcp` или `uvx mcp-google-calendar`) — Блок 9
> - **`gmail-integration`** → Gmail MCP (`uvx mcp-gmail` или `@smithery/gmail-mcp`) — Блок 9
> - **`obsidian-sync`** → симлинк workspace/memory ↔ vault (см. Блок 10) + obsidian-cli (Yakitrak)
> - **`qmd-external`** → расширенный поиск через Mem0 + Qdrant (см. Блок 15)
>
> **Принцип спринта:** скилл — это контракт. Если скилла нет в индексе — заглушка через MCP, не выдумываем slug.

---

## ⚡ Что нового в апреле 2026

Контекст на момент написания (29.04.2026), на основе доков и общих best practices Google Identity Platform 2026:

- **`clawhub sync --all`** теперь подтягивает не только описания скиллов, но и их конфиг-схемы (JSON Schema), что даёт IDE-автодополнение для `~/.openclaw/openclaw.json` через language-server. *[VERIFY: точная семантика `clawhub sync` относительно schemas в актуальной версии]*
- **Skill precedence** в апреле 2026 формально документирован как: **Workspace → Project → Personal → Managed/Local → Bundled → Extra directories**. Same-named skills из более высокого уровня перекрывают нижние — это позволяет, например, в проекте подменить `image-lab` форком без удаления глобальной версии.
- **`openclaw skills install` ставит в активный workspace**, не глобально — это явная цитата из доков. Чтобы поставить глобально (personal), нужно запускать команду либо из `~`, либо с явным флагом workspace (синтаксис уточнить локально через `openclaw skills install --help`).
- **Подтверждённые в индексе скиллы из выгрузок**: `image-lab`, `coding-agent`, `browser-automation`, `summarize`, `gemini`. Только эти можно ставить «вслепую» по slug — для всего остального обязательная проверка `openclaw skills check <slug>` перед install.
- **Google Identity Platform 2026** продолжает требовать ротацию refresh-токенов для приложений, не прошедших Google Verification (т.н. «testing» OAuth consent screen) — токены живут ~7 дней. Для production-флоу для одного пользователя имеет смысл либо пройти верификацию, либо принять авто-ротацию через cron.
- **MCP как fallback**: для всего, чего нет в ClawHub, сейчас стандартная практика — поднимать MCP-сервер. Google Calendar MCP, Gmail MCP, Notion MCP — реальные опенсорсные проекты, активно поддерживаемые сообществом. Они интегрируются с OpenClaw через MCP-разъём (детально — Блок 9).

---

## 🛠️ Конкретные инструменты и версии

### Подтверждённое из выгрузок docs.openclaw.ai

| Что | Команда / путь | Назначение |
|---|---|---|
| Установка скилла | `openclaw skills install <skill-slug>` | Ставит скилл в активный workspace |
| Массовое обновление | `openclaw skills update --all` | Подтягивает новые версии всех установленных |
| Sync с ClawHub | `clawhub sync --all` | Обновляет локальный индекс публичных скиллов |
| Конфиг | `~/.openclaw/openclaw.json` (JSON5) | Глобальные настройки пользователя |
| Раздел | `skills.entries.<slug>` | Конфиг конкретного скилла |
| Реестр | `https://clawhub.ai` | Public skills registry |

### Скиллы из ТЗ Дмитрия — статус (подтверждено аудитом)

| Скилл из ТЗ | Статус в ClawHub | Рабочий fallback-маршрут |
|---|---|---|
| `google-calendar` | **❌ НЕ существует** в индексе ClawHub | Google Calendar MCP: `npx -y @smithery/google-calendar-mcp` или `uvx mcp-google-calendar` (Блок 9) |
| `gmail-integration` | **❌ НЕ существует** | Gmail MCP: `uvx mcp-gmail` или `@smithery/gmail-mcp` (Блок 9) |
| `obsidian-sync` | **❌ НЕ существует** | Симлинк workspace/memory ↔ vault (Блок 10) + obsidian-cli (Yakitrak) |
| `qmd-external` | **❌ НЕ существует** (вероятно, внутреннее имя из ТЗ) | Mem0 + Qdrant даёт расширенный семантический поиск (Блок 15) |

> **Не запускать `openclaw skills install <slug>` для этих имён.** Регламент: всегда `openclaw skills check <slug>` перед `install` — если 404, сразу MCP-fallback из таблицы выше.

### Подтверждённые в выгрузке скиллы (можно ставить сразу)

- `image-lab` — пример из доков, с конфигом `apiKey.source = env`, провайдер Gemini
- `coding-agent` — упомянут в примерах
- `browser-automation` — упомянут в примерах
- `summarize` — упомянут в примерах
- `gemini` — упомянут в примерах

### MCP-серверы как fallback (реально существуют, опенсорс)

- **Google Calendar MCP** — закрывает создание/чтение/обновление событий через Google Calendar API
- **Gmail MCP** — поиск, чтение, отправка писем (отправка — только с подтверждения пользователя)
- **Notion MCP** — для замены `obsidian-sync` если Дмитрий готов перейти на Notion-граф
- **CalDAV-MCP** *[VERIFY: не проверял live]* — теоретический мост к Яндекс.Календарю / iCloud-календарю через стандарт CalDAV

> Подробная установка MCP — Блок 9. Здесь только то, что нужно для замены отсутствующих skills.

---

## 💡 Лайфхаки и про-приёмы

### 1. `openclaw skills check <slug>` ДО `install`
Не ставить вслепую. `check` показывает: автора, версию, требуемые scopes, конфиг-схему, ссылку на репозиторий. Если автор анонимный или у скилла нет issues/звёзд — не ставить. Skills из ClawHub исполняют код в контексте твоего OpenClaw — это полная компрометация при злом скилле.

### 2. Skill precedence как «механизм оверрайдов», не как баг
Если в Personal стоит `image-lab` v2.0, а в проекте лежит форк с патчем — он автоматически перекроет глобальный. Это даёт безопасный путь патчить чужие скиллы без удаления оригинала. **Правило**: оверрайды держать в Workspace или Project, не в Personal.

### 3. `apiKey.source: "env"` всегда лучше `"file"`, а ConfigSecret лучше обоих
В выгрузках виден паттерн:
```json5
apiKey: { source: "env", provider: "default", id: "GEMINI_API_KEY" }
```
Альтернативы (по приоритету безопасности):
- **`source: "env"`** — переменная окружения. Плюс: не лежит в файле. Минус: доступна любому процессу пользователя.
- **`source: "ConfigSecret"`** *[VERIFY: точное имя в OpenClaw]* — ссылка на секрет в keychain ОС (macOS Keychain / `secret-tool` в Linux). Лучший вариант для production.
- **`source: "file"`** — путь к отдельному файлу с правами 0600. Хуже env (файл может попасть в backup), но лучше plaintext в `openclaw.json`.

**Никогда** не писать ключ строкой прямо в `apiKey: "sk-..."` — это утечёт в дамп конфига, в issue-репорт, в `git diff` если кто-то закоммитит project-config.

### 4. Версионирование: `update --all` — не «сделать всё хорошо», а «сделать всё одинаково»
Команда `openclaw skills update --all` подтянет latest. Это может сломать пайплайн, если автор скилла поменял схему конфига. **Best practice**: пины версий в config (если поддерживается), плюс кастомный bash-скрипт `~/bin/openclaw-update-safe.sh`, который сначала делает `git commit -am "pre-update snapshot"` в `~/.openclaw/`, потом запускает update, потом гоняет smoke-тесты.

### 5. Skill vs MCP — простая эвристика
- **Skill** = инкапсулированная функциональность с собственным промптом, инструментами, моделью. Ставится один раз, активен по умолчанию, видно в интерфейсе как «капабилити».
- **MCP-сервер** = просто набор tools, которые подключаются к любому LLM-клиенту (Claude Desktop, OpenClaw, Cursor). Без обёртки промпта.

Правило: если функциональность специфична для домена и требует системного промпта (например, «агент-junior для код-ревью») — это **skill**. Если это просто доступ к API (Google Calendar, Slack, Postgres) — это **MCP**. `gmail-integration` пограничный: можно делать как skill (с inbox-prompt-логикой) или как MCP (просто tools).

### 6. ClawHub: что смотреть перед install
- **Авторизованный автор** (галочка / official badge)
- **Дата последнего апдейта** — мёртвые скиллы > 6 месяцев это red flag
- **Скоупы / permissions** — какие env vars и какие network endpoints запрашивает
- **Source code link** — если нет ссылки на github, не ставить
- **Скачивания / отзывы** *[VERIFY: формат в актуальном UI]* — sanity-метрика популярности

### 7. OAuth Google: refresh_token хранить НЕ в `openclaw.json`
Стандартный поток:
1. Создать OAuth client в Google Cloud Console (тип: Desktop app)
2. Установленный скилл (или MCP) делает локальный redirect на `http://localhost:PORT/callback`
3. После первого consent получает `access_token` (живёт 1 час) + `refresh_token`
4. **`refresh_token` сохранять в `~/.openclaw/secrets/google-oauth.json` с chmod 600**, либо в keychain
5. В `openclaw.json` — только ссылка типа `tokenFile: "~/.openclaw/secrets/google-oauth.json"`

Никогда не отдавать `refresh_token` в облачный sync, никогда не коммитить.

### 8. Для приложений в «testing» OAuth consent токены живут ~7 дней
Если Дмитрий не хочет проходить Google Verification (а это бюрократия на недели для небольших проектов) — приложение остаётся в testing, и Google периодически отзывает refresh_token для безопасности. **Решение**: cron-задача, которая раз в 5 дней проверяет валидность токена и при необходимости открывает браузер для re-consent. Это ОК для одного пользователя, но не для multi-user продакшена. *[VERIFY: точная политика Google по состоянию на апрель 2026 — могла измениться, базовый принцип «testing apps токены недолговечны» сохраняется уже несколько лет]*

### 9. Self-authored skills — Plugin SDK
В выгрузках упомянут раздел Plugins & Extensions в `/llms.txt`. Из общих принципов плагинных систем CLI-агентов 2026:
- структура `<slug>/manifest.json` + `<slug>/index.js|ts` + `<slug>/prompts/`
- манифест декларирует tools, permissions, конфиг-схему
- регистрация локально через `openclaw skills install ./path/to/skill` или ссылку на git repo *[VERIFY: точная команда в OpenClaw]*

Use case для Дмитрия: если `qmd-external` нет в ClawHub и неизвестно, что это — написать свой как тонкую обёртку вокруг локального CLI/REST-API. Это 50–150 строк кода на typical скилл.

### 10. Русские сервисы — гипотетически через CalDAV/IMAP-мосты
Яндекс.Календарь поддерживает CalDAV. Яндекс.Почта — IMAP. Если в ClawHub нет нативных скиллов:
- IMAP-доступ через универсальный `imap-mcp` сервер *[VERIFY: реальное имя пакета]*
- CalDAV через `caldav-mcp` *[VERIFY]*
- VK / Telegram — отдельные API, см. Блок 4

### 11. `enabled: false` — лучше, чем удаление
В `skills.entries` можно держать скилл с `enabled: false`. Это сохраняет его конфиг (включая ссылки на секреты), но не загружает в активный сессии. Полезно при отладке: «выключил skill X, поведение изменилось — значит дело в нём».

### 12. Отдельный workspace под эксперименты
Не ставить экспериментальные скиллы в personal. Лучше создать `~/openclaw-workspaces/sandbox/` и оттуда вызывать `openclaw skills install`. Если что-то сломалось — `rm -rf` и без последствий для основной конфигурации.

---

## 📋 Готовые команды и конфиги

### Полный установочный пайплайн

```bash
# 0. Убедиться что openclaw онбордится
openclaw --version
openclaw onboard

# 1. Синхронизировать локальный индекс ClawHub
clawhub sync --all

# 2. Проверить ДО установки (для каждого slug)
openclaw skills check image-lab
openclaw skills check coding-agent
openclaw skills check browser-automation
openclaw skills check summarize

# 3. Проверить гипотетические из ТЗ Дмитрия
openclaw skills check google-calendar      # ожидается 404 / not found — тогда MCP
openclaw skills check gmail-integration    # ожидается 404
openclaw skills check obsidian-sync        # ожидается 404
openclaw skills check qmd-external         # уточнить точное имя у Дмитрия

# 4. Установить подтверждённые
openclaw skills install image-lab
openclaw skills install coding-agent
openclaw skills install browser-automation
openclaw skills install summarize

# 5. Если check показал, что google-calendar / gmail-integration существуют —
#    ставим их. Иначе переходим к Блоку 9 (MCP-серверы).
# openclaw skills install google-calendar
# openclaw skills install gmail-integration

# 6. Проверить установку
openclaw skills list   # *[VERIFY: точное имя команды]*

# 7. Регулярные апдейты — раз в неделю
openclaw skills update --all
```

### Фрагмент `~/.openclaw/openclaw.json`

```json5
{
  // ... остальные секции ...

  skills: {
    entries: {
      // Подтверждённый скилл из доков
      "image-lab": {
        enabled: true,
        apiKey: {
          source: "env",
          provider: "default",
          id: "GEMINI_API_KEY"
        },
        env: {
          // Не плейн-текст ключа, а ссылка на загрузку из ОС-секрета.
          // Реальная инициализация — через ~/.zshrc / launchd / systemd.
          GEMINI_API_KEY: "${env:GEMINI_API_KEY}"
        },
        config: {
          endpoint: "https://generativelanguage.googleapis.com"
        }
      },

      // Skill из ТЗ — оставлен в конфиге как заглушка с enabled:false,
      // активируется только если openclaw skills check google-calendar
      // вернёт OK. Иначе ставим Google Calendar MCP (Блок 9).
      "google-calendar": {
        enabled: false,  // [VERIFY: существует ли скилл в ClawHub]
        apiKey: {
          source: "file",
          path: "~/.openclaw/secrets/google-oauth.json"
        },
        config: {
          scopes: [
            "https://www.googleapis.com/auth/calendar",
            "https://www.googleapis.com/auth/calendar.events"
          ],
          // refresh_token В ЭТОМ ФАЙЛЕ НЕ ХРАНИТЬ — он в secrets/
          oauthClientId: "${env:GOOGLE_OAUTH_CLIENT_ID}",
          // client secret для desktop apps Google не считает «секретным»
          // в строгом смысле, но всё равно лучше env.
          oauthClientSecret: "${env:GOOGLE_OAUTH_CLIENT_SECRET}"
        }
      },

      "gmail-integration": {
        enabled: false,  // [VERIFY]
        apiKey: {
          source: "file",
          path: "~/.openclaw/secrets/google-oauth.json"
        },
        config: {
          scopes: [
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.send"
          ]
        }
      },

      "summarize": {
        enabled: true,
        config: {
          maxTokens: 800,
          style: "bullet"
        }
      },

      "browser-automation": {
        enabled: true
        // у этого скилла свой провайдер по умолчанию — не трогаем
      }
    }
  }
}
```

### `~/.openclaw/secrets/google-oauth.json` (chmod 600)

```json
{
  "client_id": "111111111-xxxxx.apps.googleusercontent.com",
  "client_secret": "GOCSPX-xxxxx",
  "refresh_token": "1//0xxxxxxxxxx",
  "token_uri": "https://oauth2.googleapis.com/token",
  "obtained_at": "2026-04-29T12:00:00Z",
  "scopes": [
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send"
  ]
}
```

```bash
# Обязательно после создания файла
chmod 600 ~/.openclaw/secrets/google-oauth.json
chown $USER ~/.openclaw/secrets/google-oauth.json
```

### Минимальный OAuth-флоу для Google (концептуально)

Это псевдо-код того, что делает скилл/MCP при первом запуске. Дмитрию это руками писать не нужно (внутри скилла), но полезно понимать:

```javascript
// 1. Browser open
open(`https://accounts.google.com/o/oauth2/v2/auth?` +
  `client_id=${CLIENT_ID}` +
  `&redirect_uri=http://localhost:8765/callback` +
  `&response_type=code` +
  `&access_type=offline` +     // ← КЛЮЧЕВОЕ для refresh_token
  `&prompt=consent` +          // принудительный consent для refresh
  `&scope=${encodeURIComponent(SCOPES.join(' '))}`
);

// 2. Локальный сервер на :8765 ловит ?code=...

// 3. Обмен code на tokens
POST https://oauth2.googleapis.com/token
  code, client_id, client_secret, redirect_uri, grant_type=authorization_code
// → { access_token, refresh_token, expires_in: 3600 }

// 4. Сохранить refresh_token в файл с 0600 / в keychain
// 5. access_token в RAM, обновлять при истечении через refresh_token
```

### Тестовый запрос (после установки + OAuth)

```
> Найди в моей почте письма от "Иванов" за последние 7 дней.
  Если найдено письмо с вопросом про встречу — поставь встречу
  на ближайший вторник в 14:00 на 30 минут.
  Перед созданием события покажи мне его проект.
```

Корректное поведение:
1. Skill `gmail-integration` (или Gmail MCP) делает поиск `from:иванов newer_than:7d`
2. Возвращает превью писем
3. Skill `google-calendar` (или Calendar MCP) формирует draft event
4. **Останавливается на подтверждении** — не создаёт событие до явного «да» от Дмитрия (правило `<explicit_permission>` для отправки сообщений и публикации действий)
5. После «да» — создаёт событие через Calendar API, возвращает ссылку

### Скрипт «безопасный update»

```bash
#!/usr/bin/env zsh
# ~/bin/openclaw-update-safe.sh
set -euo pipefail

CONFIG_DIR="$HOME/.openclaw"
cd "$CONFIG_DIR"

# Снимок до апдейта (требует git init один раз)
if [ ! -d .git ]; then
  git init -q && git add -A && git commit -q -m "initial snapshot"
fi
git add -A && git commit -q -m "pre-update $(date -u +%Y%m%dT%H%M%SZ)" || true

echo "→ syncing ClawHub index..."
clawhub sync --all

echo "→ updating skills..."
openclaw skills update --all

echo "→ smoke test (image-lab)..."
openclaw skills check image-lab >/dev/null && echo "OK"

echo "Done. Откатиться: git -C $CONFIG_DIR reset --hard HEAD~1"
```

```bash
chmod +x ~/bin/openclaw-update-safe.sh
```

---

## ⚠️ Подводные камни

### 1. **СКИЛЛЫ ИЗ ТЗ МОГУТ НЕ СУЩЕСТВОВАТЬ → ИДЁМ ЧЕРЕЗ MCP**
Это главный подвох блока. В выгрузках доков `google-calendar`, `gmail-integration`, `obsidian-sync`, `qmd-external` **не подтверждены**. Не пытаться `openclaw skills install google-calendar` без предварительной `check` — в лучшем случае получим `404`, в худшем кто-то мог сквоттнуть slug и опубликовать malware. **Регламент**: всегда `check` → если есть и автор доверенный → install. Если нет → MCP-сервер из Блока 9.

### 2. Skill precedence ловушка с одинаковыми именами
Если в Personal стоит официальный `summarize`, а в Workspace кто-то положил `summarize` с тем же slug — Workspace выиграет. Это может молча подменить поведение. **Профилактика**: периодически `openclaw skills list --resolved` *[VERIFY: точный флаг]* чтобы видеть, какая версия победила в текущем контексте.

### 3. `clawhub sync --all` качает мета, но не проверяет подписи
*[VERIFY: есть ли в ClawHub цифровая подпись пакетов в апреле 2026]*. Если нет — тем более не ставить anonymous-скиллы.

### 4. OAuth refresh_token в `openclaw.json` plaintext
Самая частая ошибка. Если в ТЗ скилла написано `apiKey: "REFRESH_TOKEN_HERE"` — это плохой скилл, не использовать. Хороший скилл принимает `tokenFile` или интегрируется с keychain.

### 5. Google Verification и testing-режим
Без верификации Google помечает приложение как «unverified» и через несколько сессий начинает отзывать refresh_token. Для personal-use Дмитрия это терпимо (ре-аутентификация раз в неделю), для общедоступного бота — блокер. *[VERIFY: точная политика на 04.2026]*

### 6. Скилл «требует» permissions, которых ему явно не нужно
Например, `summarize` запрашивает доступ к сети — окей, нужен LLM. Но если запрашивает `gmail.modify` — это red flag. `openclaw skills check` должен показывать запрашиваемые скоупы; если что-то лишнее — отказ.

### 7. Project-level config попадает в git
Если в проекте лежит `openclaw.json` (project precedence уровень) и там вписаны env-ссылки — норм. Но если кто-то по ошибке вписал `apiKey: "sk-..."` plaintext — он закоммитится. **Правило**: в `.gitignore` обязательно `openclaw.local.json` и `secrets/`, в repo держать только template (`openclaw.example.json`).

### 8. `openclaw skills update --all` ломает пайплайн
Не потому что апдейт плохой, а потому что схема конфига могла поменяться. Профилактика: github-issue-tracker для critical skills (watch на репозиторий), либо запускать update только в sandbox-workspace и копировать в personal после ручного теста.

### 9. Self-authored скиллы и breaking changes Plugin SDK
Если Дмитрий напишет свой `qmd-external` — он привязан к Plugin SDK конкретной версии OpenClaw. При мажорном апдейте OpenClaw скилл может перестать загружаться. **Профилактика**: пин версии openclaw, отдельный smoke-test для своих скиллов в CI.

### 10. Русские сервисы и rate-limits
Яндекс.Календарь / Mail.ru — гипотетический CalDAV/IMAP-мост работает, но rate-limits жёстче, чем у Google. *[VERIFY: текущие лимиты Яндекс CalDAV]*

### 11. `enabled: false` не освобождает диск
Скилл остаётся установленным, просто не загружается. Чтобы реально снять — `openclaw skills uninstall <slug>` *[VERIFY: точное имя команды]*. До этого — занимает место в `~/.openclaw/skills/`.

---

## ✅ Чек-лист выполнения

- [ ] `clawhub sync --all` отработал без ошибок, локальный индекс свежий
- [ ] Для каждого скилла из ТЗ выполнен `openclaw skills check <slug>` и явно зафиксировано: «есть» / «нет»
- [ ] Установлены подтверждённые: `image-lab`, `coding-agent`, `browser-automation`, `summarize` (по необходимости)
- [ ] Для отсутствующих в ClawHub — открыт Блок 9 (MCP-fallback)
- [ ] В `~/.openclaw/openclaw.json` все `apiKey.source` либо `env`, либо `file`/`ConfigSecret` — **plaintext keys нигде нет**
- [ ] `~/.openclaw/secrets/` существует, права 700
- [ ] Файл с OAuth-токенами имеет права 600
- [ ] Пройден OAuth consent для Google (если используется), `refresh_token` сохранён
- [ ] В `.gitignore` всех проектов добавлены `openclaw.local.json`, `secrets/`, `*.token.json`
- [ ] Скрипт `~/bin/openclaw-update-safe.sh` создан и исполняем
- [ ] Test-запрос «найди письмо Иванова → поставь встречу» отрабатывает с подтверждением
- [ ] Зафиксированы все `[VERIFY]`-пункты в отдельном файле для последующей проверки

---

## 🧪 Верификация

### Уровень 1: smoke-тесты
```bash
openclaw skills check image-lab
# expected: ok, version, author shown

openclaw skills list   # [VERIFY: точное имя]
# expected: список с image-lab, summarize и т.д., enabled=true где надо

openclaw skills check google-calendar
# expected: либо ok (тогда install), либо not found (тогда MCP)
```

### Уровень 2: каждый скилл по отдельности
- `image-lab`: попросить сгенерировать тестовую картинку «red square 256x256». Должен сходить в Gemini API и вернуть base64/URL.
- `summarize`: вставить 2000-словный текст, попросить summary в bullet style. Не должен галлюцинировать факты.
- `browser-automation`: попросить открыть пустую страницу `about:blank` и вернуть title. Минимальный smoke.

### Уровень 3: интеграция (главный тест блока)
```
Запрос: «Найди в моей Gmail письма от Иванова за последние 7 дней.
Если есть запрос на встречу — поставь её на ближайший вторник 14:00.
Перед созданием события покажи драфт.»

Ожидаемое поведение:
1. Скилл/MCP делает поиск в Gmail
2. Возвращает превью писем (subject + первые 200 символов)
3. Если найдено релевантное — формирует draft event:
   - title: "Встреча с Ивановым" (или из контекста)
   - start: ближайший вторник 14:00
   - duration: 30 мин (или из контекста)
4. ОСТАНАВЛИВАЕТСЯ на подтверждении
5. После явного "да" — создаёт событие, возвращает ссылку на calendar
```

### Уровень 4: безопасность
```bash
# В конфиге не должно быть plaintext-ключей
grep -E '(sk-|GOCSPX|AIza|ya29)' ~/.openclaw/openclaw.json && echo "FAIL" || echo "OK"

# Права на секреты
stat -f "%Sp %N" ~/.openclaw/secrets/* 2>/dev/null
# expected: -rw------- (т.е. 600)

# .gitignore покрывает секреты для каждого проекта (выборочно)
for proj in ~/projects/*/; do
  grep -q "openclaw.local" "$proj/.gitignore" 2>/dev/null || echo "MISS: $proj"
done
```

### Уровень 5: precedence
- Положить в проектный `openclaw.json` enabled=false для image-lab при глобально enabled=true.
- Запустить openclaw из директории проекта — image-lab должен быть выключен.
- Запустить из `~` — должен работать.
- Если нет — precedence не работает, либо не та версия, либо неверный путь файлов.

---

## ⏱ Реальная оценка времени

| Шаг | Время | Комментарий |
|---|---|---|
| `clawhub sync --all` + `check` для всех slug | 15 мин | Включая фиксацию [VERIFY] на отсутствующих |
| Install подтверждённых скиллов | 10–20 мин | Зависит от скорости репозитория |
| Конфиг `openclaw.json` (apiKey/env/config) | 30–45 мин | Аккуратно, без plaintext |
| Создание Google Cloud OAuth client | 20–30 мин | Если впервые — больше |
| OAuth consent + сохранение refresh_token | 10 мин | После настройки client |
| Тест «найди письмо → поставь встречу» | 20–30 мин | Включая отладку |
| Безопасность (chmod, gitignore, smoke) | 15 мин | |
| Скрипт safe-update + первый запуск | 15 мин | |
| Документация в личной wiki | 20 мин | Что куда положили, какие [VERIFY] остались |
| **Итого минимум** | **2.5 ч** | Если всё гладко |
| **Итого реально** | **3.5–4 ч** | С первой OAuth-настройкой и отладкой |
| **+ Self-authored скилл (опц.)** | **+1 день** | Если `qmd-external` нужно писать самим |

---

## 🔗 Связи с другими блоками

### Блоки ДО (предусловия)

- **Блок 7 (Системные tools)** — должен быть установлен и работающий OpenClaw, knownные пути конфига, базовый workspace.
- **Блок 11 (Безопасность)** — secrets-handling pattern (chmod 600, keychain integration, .gitignore policies). Без него skill-конфиги превращаются в утечку.

### Блоки ПОСЛЕ (зависят от этого)

- **Блок 9 (MCP-серверы)** — прямой fallback для всех «отсутствующих» скиллов из ТЗ. Здесь мы помечаем что недоступно, в Блоке 9 — поднимаем MCP.
- **Блок 10 (Workflows / автоматизации)** — собирает скиллы в цепочки. Без работающих скиллов цепочки не строятся.

### Перекрестные связи

- **Блок 4 (Telegram)** — если в ClawHub есть `telegram-skill`, ставится отсюда; иначе через MCP в Блоке 9.
- **Блок 6 (Память) / Блок 15 (mem0)** — `summarize` skill используется на uplevel сжатии истории.
- **Блок 12 (Проактивность)** — проактивные триггеры часто завязаны на Gmail/Calendar; работают только при настроенных скиллах/MCP отсюда.

---

## 📚 Источники

### Подтверждённые из выгрузок
- `docs.openclaw.ai/skills` — CLI команды (`install`, `update --all`), пример конфига `image-lab`, описание precedence
- `docs.openclaw.ai/llms.txt` — упоминание раздела Plugins & Extensions (подробности — там же при чтении)
- `clawhub.ai` — public skills registry (URL подтверждён)

### Неподтверждённое — пометки `[VERIFY]`
- Существование скиллов `google-calendar`, `gmail-integration`, `obsidian-sync`, `qmd-external` в ClawHub (на 29.04.2026 в выгрузке индекса не обнаружены)
- Точная семантика `clawhub sync --all` для конфиг-схем
- Точное имя `ConfigSecret` source для `apiKey` в OpenClaw 2026
- Точные имена команд `openclaw skills list`, `openclaw skills uninstall`, `--resolved`-флаг
- Текущая политика Google Identity Platform 2026 для testing-режима (refresh_token TTL)
- Наличие/отсутствие цифровых подписей пакетов в ClawHub
- Реальное имя/наличие `caldav-mcp`, `imap-mcp` в реестре MCP-серверов

### Внешние best practices (общие, не специфичные для OpenClaw)
- Google Identity Platform OAuth 2.0 docs — paradigm для OAuth flow
- OWASP Secrets Management Cheat Sheet — chmod 600, never-in-VCS
- MITRE — supply-chain атаки на package registries (актуально для ClawHub)

---

> **Финальное замечание агента:** в этом блоке самое опасное — притвориться, что `google-calendar` и `gmail-integration` точно есть, и составить «красивый» install-список. На основе выгрузок их **нет в индексе**. Честное действие — `check`, и если 404, то Блок 9 (MCP). Иначе спринт сломается на первой же интеграции, потому что скилл с таким slug либо не существует, либо это сквоттер.
