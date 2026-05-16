# Подготовка к Воркшопу 3 — 25 минут накануне

> Это домашка ДО старта В3. Без неё на воркшопе зависнешь на регистрациях.
> Когда закончишь — на В3 уже будет всё необходимое: подписки, ключи, отдельная почта.

---

## Что собираем

| # | Что | Где | Время | Сложность |
|---|---|---|---|---|
| 1 | Отдельная ботовая Gmail | accounts.google.com | 3 мин | 🟢 Просто |
| 2 | Подписка ChatGPT Plus ($20/мес) | chat.openai.com | 2 мин | 🟢 Просто |
| 3 | Brave Search API ключ (free 2000/мес) | brave.com/search/api/ | 3 мин | 🟢 Просто |
| 4 | Tavily API ключ (free 1000/мес) | tavily.com | 3 мин | 🟢 Просто |
| 5 | Google Cloud Console OAuth → `client_secret.json` | console.cloud.google.com | 12 мин | 🟡 Самое сложное |
| 6 | (опц) DataImpulse прокси | dataimpulse.com | 5 мин | 💡 Только если работаешь с гео-блоками |

---

## Шаг 1 — Завести ботовую Gmail (3 мин)

**Почему отдельная.** В3 даём боту доступ к Gmail и Calendar. Если использовать личную почту — бот через ошибку может удалить важное письмо или отправить от твоего имени. Отдельный ботовый аккаунт = чистая граница.

**Что делать:**
1. Открой **инкогнито-окно** в Chrome/Safari (важно: не мешать своему Google-аккаунту)
2. `accounts.google.com` → «Create account» → «For my personal use»
3. Имя: любое (например `Openclaw Bot` или `<твоё имя> Bot`)
4. Username: `<твоё-имя>-openclaw@gmail.com` или подобное — придумай свой
5. Пароль → 2FA по желанию (если включаешь — запоминай куда привязал)
6. **Сохрани логин + пароль в менеджер паролей** (1Password / Apple Keychain / Bitwarden). Без этого через месяц забудешь и потеряешь доступ к боту.

**Готово:** у тебя есть отдельный Google-аккаунт под бота. На него пойдут все регистрации/OAuth дальше.

---

## Шаг 2 — Подписка ChatGPT Plus (2 мин)

**Зачем.** В3 переходим на GPT-5 как primary модель бота. Доступ через Codex CLI OAuth — официальный способ OpenAI. Подписка $20/мес даёт безлимит на GPT-5 в боте.

**Что делать:**
1. `chat.openai.com` → залогинься (любым аккаунтом, не обязательно ботовым)
2. В левом нижнем углу — твой профиль → «Upgrade plan»
3. Plus — $20/мес → оплати

**Если уже есть Plus** — пропусти шаг.

**Готово:** подписка активна. Codex CLI на VPS сможет авторизоваться через ChatGPT-OAuth и получать доступ к GPT-5.

---

## Шаг 3 — Brave Search API ключ (3 мин)

**Зачем.** Бесплатные 2000 поисковых запросов в месяц для бота. Это `web_search` инструмент — когда боту нужно загуглить что-то.

**Что делать:**
1. `brave.com/search/api/` → «Get Started»
2. Зарегистрируйся (email подойдёт ботовый или личный — не критично)
3. Subscribe → «Free plan» → 2000 queries/month
4. Без карты — бесплатно
5. В Dashboard → «API Keys» → скопируй ключ (формат `BSA...`)
6. Сохрани в заметках как `BRAVE_API_KEY=BSA...`

---

## Шаг 4 — Tavily API ключ (3 мин)

**Зачем.** Bторой поисковик — но для **глубокого ресёрча**. Tavily возвращает структурированные данные специально для AI-агентов (а не HTML-страницы как Brave). Free tier 1000 запросов/мес.

**Что делать:**
1. `tavily.com` → «Sign up» → почта (можно ботовая)
2. В Dashboard → копируй API key (формат `tvly-...`)
3. Сохрани в заметках как `TAVILY_API_KEY=tvly-...`

---

## Шаг 5 — Google Cloud Console (12 мин, самое сложное)

**Зачем.** Чтобы бот мог читать Gmail и Calendar — нужен OAuth. OAuth настраивается в Google Cloud Console. На выходе получишь файл `client_secret.json` который скармливаешь боту.

**ВАЖНО:** весь этот шаг делается **под ботовой Gmail** из Шага 1, не под личным аккаунтом!

### Часть 5.1 — Создать проект

1. Открой **инкогнито-окно** → `console.cloud.google.com`
2. Залогинься **ботовой почтой** (та что в Шаге 1 создал)
3. Если первый раз — Accept Terms
4. Сверху dropdown «Select a project» → «NEW PROJECT»
5. Name: `openclaw-bot`
6. Location: leave «No organization»
7. CREATE → ждёшь 30 сек
8. Сверху Switch to project (если не переключился сам)

### Часть 5.2 — Включить 2 API

1. Левое меню (☰) → «APIs & Services» → «Library»
2. В поиске введи **«Gmail API»** → клик на результат → синяя кнопка **ENABLE**
3. Назад в Library → поиск **«Google Calendar API»** → ENABLE

### Часть 5.3 — OAuth Consent Screen (новое название — **Google Auth Platform**)

⚠️ **В новом интерфейсе Google Cloud Console (2025-2026) переименовано:** раздел «OAuth consent screen» теперь часто называется **«Google Auth Platform»**, а внутри него — пункты `Branding` / `Audience` / `Clients` / `Data Access`. Старое название «OAuth consent screen» может ещё встречаться в проектах созданных до апреля 2025.

Это публичная страница которую увидишь при авторизации бота — что-то типа «Openclaw-bot хочет доступ к Gmail и Calendar».

1. ☰ → **APIs & Services** → **OAuth consent screen** (или **Google Auth Platform** → **Branding**)
2. Если первый раз — нажми «Get Started»
3. App name: `openclaw-bot`
4. User support email: твоя ботовая почта
5. Developer contact: твоя ботовая почта
6. User Type: **External**
7. Save and Continue

### Часть 5.4 — Data Access (бывшие Scopes)

⚠️ **Это бывшие Scopes** — название изменилось.

1. В разделе OAuth consent screen / Google Auth Platform слева ищи пункт **«Data Access»** (раньше назывался «Scopes»)
2. Нажми **«Add or Remove Scopes»**
3. В фильтре введи **«gmail»** → выбери чекбоксами:
   - `.../auth/gmail.readonly` (читать почту)
   - `.../auth/gmail.send` (отправлять почту)
4. В фильтре введи **«calendar»** → выбери:
   - `.../auth/calendar.events.readonly` (читать события)
   - `.../auth/calendar.readonly` (читать календарь)
5. **Update** (внизу) → **Save**

### Часть 5.5 — Audience (Test Users тут!)

⚠️ **Test Users больше не отдельная страница** — они внутри пункта **«Audience»**.

1. В разделе OAuth consent screen / Google Auth Platform слева → **«Audience»**
2. Прокрути вниз до секции **«Test users»**
3. **+ Add users** → введи свою **ботовую почту** (ту что в Шаге 1 создал — да, ту же, на ней будет авторизация)
4. ADD → Save

⚠️ Без этого шага OAuth flow выдаст ошибку «access blocked». Test users нужны пока статус приложения «Testing».

### Часть 5.6 — Создать OAuth Client ID (Credentials — отдельный пункт меню!)

⚠️ **Credentials — это ОТДЕЛЬНЫЙ пункт меню**, не внутри OAuth consent screen. Соседний с ним.

1. ☰ → **APIs & Services** → **Credentials** (не внутри «OAuth consent screen» — рядом!)
2. Сверху **«+ Create Credentials»** → **«OAuth client ID»**
3. Application type: **Desktop app**
4. Name: `openclaw-bot-desktop`
5. **CREATE**
6. Появится модалка с **Client ID** и **Client Secret** → нажми **«Download JSON»** → файл `client_secret_XXXX.json` уйдёт в Downloads

### Часть 5.7 — Запиши значения

1. Открой `client_secret_XXXX.json` в TextEdit
2. Найди и **скопируй**:
   - `client_id`: значение в кавычках (формат `123456-abc.apps.googleusercontent.com`)
   - `client_secret`: значение в кавычках (формат `GOCSPX-...`)
3. Сохрани в заметках:
   - `GOOGLE_OAUTH_CLIENT_ID=123456-abc.apps.googleusercontent.com`
   - `GOOGLE_OAUTH_CLIENT_SECRET=GOCSPX-...`
4. **Сам файл `client_secret_XXXX.json` не удаляй** — он понадобится на В3 (Antigravity положит его на VPS).

---

## Шаг 6 — DataImpulse прокси (опц, 5 мин)

**Когда нужно:**
- Работаешь с сайтами которые **геоблокируют** (например booking.com показывает разные цены из разных стран)
- Сайт агрессивно банит датацентровые IP (Cloudflare-защищённые)
- Нужно собирать данные с нескольких аккаунтов без bana

**Когда НЕ нужно:**
- Простой поиск, чтение статей, бронирование столиков — Patchright + Xvfb справятся без residential proxy

**Что делать (если решил ставить):**
1. `dataimpulse.com` → Sign Up → почта (можно ботовая)
2. Top Up balance — минимум $1 (1 GB трафика, хватает на месяцы для бота)
3. Dashboard → «Residential proxy» → копируй:
   - Username (формат `XXXX-USERNAME`)
   - Password
4. Сохрани:
   - `PROXY_USER=XXXX-USERNAME`
   - `PROXY_PASS=...`

---

## Итог подготовки — что у тебя в заметках

После всех шагов в твоих заметках (или в .env-черновике) должно быть:

```
# Шаг 1 — ботовая почта
BOT_EMAIL=my-name-openclaw@gmail.com
BOT_PASSWORD=сохранён в менеджере паролей

# Шаг 2 — ChatGPT Plus подписка — активна

# Шаг 3
BRAVE_API_KEY=BSA-xxxxxxxxxxxxx

# Шаг 4
TAVILY_API_KEY=tvly-xxxxxxxxxxxxx

# Шаг 5
GOOGLE_OAUTH_CLIENT_ID=123456-abc.apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=GOCSPX-xxxxxxxxxxxxx
# Файл client_secret_XXXX.json лежит в Downloads

# Шаг 6 (опц)
PROXY_USER=XXXX-username
PROXY_PASS=xxxxxxxxxxxxx
```

---

## Когда стартовать В3

Когда есть всё что выше — открывай интерактивный гайд В3 и иди по промптам. Подготовка тебе сэкономит 25 минут на самом воркшопе — будем сразу настраивать стек, а не регистрироваться по сайтам.

**Если что-то не получилось** на одном из шагов — пиши в чат когорты, разберёмся. Не пропускай — без любого из шагов (1-5) воркшоп заблокируется.

— Дмитрий Попов / @ai_comandos
