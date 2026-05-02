# Блок 4: Telegram-канал

> Что: подключение Telegram-бота к OpenClaw как «голоса» агента — единственный канал общения, доступный только хозяину.
> Зачем: чтобы Дмитрий мог общаться со своим AI-агентом из любой точки мира с телефона, при этом никто посторонний не сможет влезть в чат и стрелять командами.
> Время: 25-35 минут (с учётом тестов и переключения с pairing на allowlist).

---

## Целевой результат блока

К концу блока должно быть:
1. Создан Telegram-бот через @BotFather с правильными настройками Privacy/Groups/Inline.
2. Токен прописан в `~/.openclaw/openclaw.json` через переменную окружения (НЕ в открытом виде).
3. Получен numeric `user_id` Дмитрия (через @userinfobot или getUpdates).
4. Канал переведён с `dmPolicy: pairing` на `dmPolicy: allowlist` с одним numeric ID.
5. Hello World тест проходит: «Привет, кто ты?» — агент отвечает.
6. Контр-тест: с другого аккаунта/телефона жены/друга бот игнорирует сообщения.
7. Заложен фундамент под Forum Supergroup для Блока 16 (мульти-агенты в одном чате через топики).

---

## Что нового в апреле 2026

**Telegram Bot API 9.6** (3 апреля 2026) — самая свежая версия, доступная в OpenClaw. Ключевое для агента:

- **Bot API 9.5 (1 марта 2026)** — `sendMessageDraft` для стриминга частичных сообщений во время генерации. Это критично: вместо `editMessageText` каждые 200мс (что упирается в rate limit) теперь нативный API для «печатает...» в реальном времени.
- **Bot API 9.3 (декабрь 2025)** — Forum Topics распространены на приватные чаты (не только супергруппы). Раньше топики были только для супергрупп — теперь Дмитрий может разделить свой личный диалог с ботом на потоки (например, «Работа», «Идеи», «Инбокс»).
- **Bot API 9.0-9.2** — Telegram Stars (XTR) полноценно поддерживается. Если в будущем Дмитрий захочет монетизировать своего агента — встроенный механизм без Stripe/Paddle.
- **Bot API 8.0 (сентябрь 2024)** — Mini Apps в полноэкранном режиме, запуск с домашнего экрана. Пригодится для Блока 16 как UI для управления агентами.
- **Custom Emoji + Reactions API** — `setMessageReaction`. Лайфхак: бот может ставить «👀» на ваше сообщение когда «прочитал», «✅» когда выполнил, «🤔» когда думает. Это дешевле чем typing-индикатор и нагляднее.
- **Managed Bots (9.6, апрель 2026)** — новые методы для создания «суббота» из бота. Релевантно для мульти-агентной архитектуры.

**Что важно НЕ изменилось:**
- Rate limits: 1 msg/sec в один чат, 20 msg/min в группу, 30 msg/sec общий broadcast. Эти цифры — народные, Telegram официально их не публикует, но плясать надо от них.
- Размер файла бота: 50MB на скачивание, 50MB на загрузку через Bot API. Если нужно больше — только TDLib/MTProto (не наш случай).

---

## Конкретные инструменты и версии

| Инструмент | Версия / адрес | Зачем |
|------------|----------------|-------|
| @BotFather | t.me/BotFather (официальный) | Создание бота, получение токена, настройка privacy/commands |
| @userinfobot | t.me/userinfobot | Получение numeric user_id (не username!) |
| @JsonDumpBot | t.me/JsonDumpBot | Альтернатива, показывает полный JSON `from` |
| @getmyid_bot | t.me/getmyid_bot | Третья альтернатива на случай если первые две заблокированы |
| Telegram Bot API | 9.6 (3 апреля 2026) | Базовый API |
| OpenClaw | 2026.4.x | Чем свежее, тем стабильнее pairing flow |
| `curl` | системный | Для дёрганья `/getUpdates` напрямую |
| `jq` | brew install jq | Парсинг JSON ответа от Telegram API |

**Долгое поллинг vs Webhook (что использует OpenClaw):**
- По умолчанию OpenClaw включает **long polling** — `getUpdates` с таймаутом, один поллер на токен. Stall detection перезапускает поллер через 120с (настраивается `pollingStallThresholdMs`, диапазон 30-600 секунд).
- Webhook доступен через `webhookUrl` + `webhookSecret`. Нужен только если у вас публичный домен с HTTPS (TLS обязателен), готовый принимать POST.
- **Рекомендация для Дмитрия:** оставить long polling. Webhook потребует пробрасывать порт через VPS, возиться с Let's Encrypt, и любая ошибка в `webhookSecret` = беззащитный endpoint. Polling работает из коробки, latency 200-500мс — для личного агента это незаметно.

---

## Лайфхаки и про-приёмы (10 штук)

1. **Numeric user_id, а НЕ username.** Username (`@dmitriypopov`) можно сменить за 5 секунд в настройках Telegram, и тогда allowlist сломается. Numeric ID (например `123456789`) — пожизненный, привязан к аккаунту от создания. ВСЕГДА используйте numeric.

2. **Получи user_id через `getUpdates`, а не через бота-помощника.** Боты типа @userinfobot могут быть скомпрометированы или показывать ID не вашего основного аккаунта (а форвардом). Самый надёжный способ — отправь любое сообщение своему боту, потом сделай `curl https://api.telegram.org/bot<TOKEN>/getUpdates | jq '.result[].message.from.id'`. Это твой настоящий ID.

3. **Privacy Mode в BotFather: оставь ENABLED.** По умолчанию `Privacy Mode: enabled` — бот видит в группах только сообщения, которые начинаются с `/команда` или содержат `@упоминание_бота`. Это ИДЕАЛЬНО для безопасности и для будущего Блока 16. Disable нужен только если бот должен читать ВСЕ сообщения в группе (например, для модерации).

4. **Pairing — это не «навсегда».** Pairing-код живёт 1 час и используется один раз. После approve пара сохраняется в локальный store. Это безопасно — никто за этот час не успеет угадать 8-символьный код (без `0OI1`). НО: pairing даёт DM-доступ, а групповая авторизация остаётся за `groupAllowFrom`. Это два разных механизма.

5. **Сразу после первого pairing подложи свой ID в allowFrom и сноси `dmPolicy: pairing`.** Pairing — это onboarding. После того как ты добавил себя — фиксируй в allowlist:
   ```json5
   { dmPolicy: "allowlist", allowFrom: ["123456789"] }
   ```
   Так если кто-то узнает username бота и напишет — ему даже pairing-кода не выдадут, моментальный отказ.

6. **Воспринимай голосовые как «непроверенный текст».** OpenClaw транскрибирует voice-notes (Блок 20, Whisper) и помечает их как `untrusted text` для защиты от prompt-injection. Это значит, что если кто-то перешлёт тебе голосовуху с командой «удали все файлы» — агент её НЕ выполнит как команду, только как контекст. Полезно знать, как работает.

7. **Включи `[[audio_as_voice]]` для исходящих голосовух.** Чтобы агент отвечал голосом (Блок 20, ElevenLabs/OpenAI TTS), в reply надо добавлять тег `[[audio_as_voice]]`. Иначе Telegram отправит как обычный аудиофайл с обложкой — выглядит как-то по-канцелярски и не воспроизводится в одно касание.

8. **Edit message vs new message — что выбирает OpenClaw.** Для текстовых ответов OpenClaw держит одно preview-сообщение и обновляет его через `editMessageText` (стриминг). Для медиа (картинки, файлы) — финальная отправка одним блоком. Если preview старше ~1 минуты — отправляется НОВОЕ финальное сообщение, чтобы timestamp совпадал с моментом завершения. Это правильное поведение, не ломай его.

9. **Forum Supergroup — заранее создай для Блока 16.** Создай сейчас супергруппу (Settings → Topics → enabled), добавь туда бота как админа. Один топик = один агент. Session key в OpenClaw: `agent:id:telegram:group:<chatId>:topic:<threadId>`. Топик с `threadId=1` — это General, и для него `message_thread_id` НЕ передаётся (Telegram отвергает такой запрос).

10. **`mediaMaxMb: 100` — крутни выше для книг и видео.** Дефолт OpenClaw — 100MB на одну медиа. Bot API технически даёт 50MB на загрузку, но OpenClaw умеет дробить. Если планируешь скармливать агенту PDF-книги или короткие видео — поставь `200`. Если только текст — оставь `50` (меньше нагрузки).

11. **БОНУС: один бот на всех агентов через топики, а не множество ботов.** Соблазн создать @ZuBot, @CoderBot, @ResearcherBot и собирать токены — НЕ ДЕЛАЙ. Лимит boards в Telegram, каждый бот — отдельный токен (риск утечки). Правильно: один бот, форум-супергруппа, разные топики с разными `agentId`. Так и rate-limits общие, и auth один, и UI чище.

12. **БОНУС: реакции вместо «typing...».** `setMessageReaction` дешевле чем typing-индикатор, который каждые 5 секунд надо повторять. Поставь «👀» в начале обработки и «✅» в конце — это и метка прочитано, и feedback. Лайфхак из BotNews канала.

---

## Готовые команды и конфиги

### BotFather диалог (пошагово)

```
Ты: /newbot
BotFather: Alright, a new bot. How are we going to call it?
Ты: Дмитрий Опус Помощник                  ← display name (можно менять потом)

BotFather: Good. Now let's choose a username...
Ты: dmitriy_opus_assistant_bot              ← username, должен оканчиваться на _bot

BotFather: Done! Use this token: 7XXXXXX:AAH...   ← СОХРАНИ В МЕНЕДЖЕР ПАРОЛЕЙ

# Теперь настройки:
Ты: /mybots → выбираешь бота → Bot Settings

# 1. Privacy Mode — оставить ENABLED (Privacy mode: enabled)
# 2. Allow Groups? — ENABLE (нужно для Блока 16)
# 3. Inline Mode — DISABLE (агенту не нужен inline для personal use)
# 4. Payments — пока DISABLE (Stars подключим если понадобится)

# Команды (для UI):
Ты: /setcommands
Ты: выбираешь бота
Ты: 
start - Начать диалог с агентом
status - Состояние систем
help - Справка
mode - Переключить режим (work/idea/inbox)
```

### Получение numeric user_id (3 способа)

**Способ 1 (рекомендуемый, без посредников):**
```bash
# Замени <TOKEN> на токен бота
# Сначала отправь любое сообщение боту в Telegram, потом:
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | jq '.result[].message.from'
# Получишь объект:
# { "id": 123456789, "is_bot": false, "first_name": "Дмитрий", "username": "dmitriypopov", ... }
# Цифра в "id" — это твой numeric user_id.
```

**Способ 2 (через @userinfobot):**
```
В Telegram → @userinfobot → нажать START
Бот ответит:
  Id: 123456789
  First: Дмитрий
  Username: @dmitriypopov
  Language: ru
```

**Способ 3 (через @JsonDumpBot — даёт полный JSON):**
```
В Telegram → @JsonDumpBot → отправь любое сообщение
Получишь полный JSON message с полем "from": { "id": 123456789, ... }
```

### Полный фрагмент `~/.openclaw/openclaw.json` для Telegram

```json5
{
  channels: {
    telegram: {
      enabled: true,
      defaultAccount: "main",

      // Глобальный fallback — но лучше переопределить per-account
      mediaMaxMb: 200,                       // лимит на медиа в Telegram (PDF, видео)
      pollingStallThresholdMs: 120000,       // restart polling если завис на 2мин

      accounts: {
        main: {
          // НЕ КЛАДИ ТОКЕН СЮДА В ОТКРЫТОМ ВИДЕ
          // Используй ENV — OpenClaw подхватывает $TELEGRAM_BOT_TOKEN для default account
          // Либо tokenFile с правами 600
          tokenFile: "/home/dmitriy/.openclaw/secrets/telegram_main.token",

          dmPolicy: "allowlist",              // <-- после первичного pairing
          allowFrom: ["123456789"],           // <-- твой numeric user_id (НЕ username!)

          // Защита от случайных приглашений в чужие группы
          groupPolicy: "allowlist",
          groupAllowFrom: ["123456789"],     // только Дмитрий может пинговать в группах

          // Forum Supergroup для Блока 16 (заранее)
          groups: {
            "-1001234567890": {              // chatId твоей супергруппы
              groupPolicy: "allowlist",
              groupAllowFrom: ["123456789"],
              requireMention: false,         // в личной супергруппе не нужно @упоминание
              topics: {
                "1":  { agentId: "main"     },  // General → главный агент
                "3":  { agentId: "zu"       },  // Zu (Блок 5)
                "5":  { agentId: "coder"    },  // кодер
                "7":  { agentId: "research" },  // ресерчер
              },
            },
            // Запрет всех других групп
          },
        },
      },
    },
  },
}
```

### Безопасное хранение токена (Блок 11)

```bash
# 1. Создаём папку для секретов
mkdir -p ~/.openclaw/secrets
chmod 700 ~/.openclaw/secrets

# 2. Кладём токен в файл (никаких echo в shell history!)
# Открываем редактор, вставляем токен, сохраняем
nano ~/.openclaw/secrets/telegram_main.token
chmod 600 ~/.openclaw/secrets/telegram_main.token

# 3. Альтернатива через env (для systemd units)
sudo nano /etc/openclaw/env
# В файле: TELEGRAM_BOT_TOKEN=7XXXXXX:AAH...
sudo chmod 600 /etc/openclaw/env
sudo chown openclaw:openclaw /etc/openclaw/env

# 4. ОБЯЗАТЕЛЬНО проверь .gitignore
cd ~/your-openclaw-config-repo
echo "secrets/" >> .gitignore
echo "*.token" >> .gitignore
echo "openclaw.json" >> .gitignore  # если в репо есть пример — переименуй в openclaw.example.json
```

### Pairing flow (первый запуск)

```bash
# 1. Запусти OpenClaw
openclaw start

# 2. В Telegram отправь боту /start или просто "привет"
# Бот ответит pairing-кодом — НЕ ВВОДИ его боту, а возьми из логов OpenClaw

# 3. На VPS:
openclaw pairing list telegram
# Получишь список pending: [ABCD1234] от user 123456789

openclaw pairing approve telegram ABCD1234
# Готово. Твой numeric ID добавлен в commands.ownerAllowFrom

# 4. Теперь переключи на allowlist (этот шаг ВАЖЕН!)
nano ~/.openclaw/openclaw.json
# Замени dmPolicy: "pairing" на dmPolicy: "allowlist"
# Добавь allowFrom: ["123456789"]

# 5. Перезапусти
openclaw restart
```

---

## Подводные камни

1. **Pairing уязвимость (низкая, но есть).** Если злоумышленник узнает username бота и напишет ему ровно в момент когда ты ждёшь pairing-код — он может перехватить approval, если ты невнимательно одобришь не свой код. Митигация: код всегда в логах с `from.id` — сверяй ID. Лучше после первого approve СРАЗУ переходи на allowlist.

2. **Username vs numeric ID.** Самая частая ошибка новичков. `@dmitriypopov` — НЕ ID. Если положишь в allowFrom строку с `@`, OpenClaw скорее всего отвергнет конфиг (валидация ждёт numeric). Префиксы `telegram:` и `tg:` работают, но всё равно с цифрами: `"telegram:123456789"`.

3. **Privacy Mode по умолчанию ENABLED.** В супергруппе бот не получит твоё сообщение, если оно не начинается с `/команды` и не содержит `@bot_username`. Это фича, не баг. Если ты в Блоке 16 настраиваешь Forum и удивляешься почему бот молчит — проверь Privacy Mode и `requireMention`.

4. **Rate limits.** 30 msg/sec общий, 1 msg/sec в один чат, 20 msg/min в группу. При стриминге через `editMessageText` каждый edit считается. OpenClaw это понимает и троттлит — но если ты пишешь свои хуки, помни. 429 Too Many Requests = временный бан, респектируй `retry_after`.

5. **Пустой allowlist = тотальный блок.** `dmPolicy: "allowlist"` с пустым `allowFrom: []` — конфиг отвергается валидацией OpenClaw. Если хочешь временно отключить DM — `dmPolicy: "disabled"`, не пустой массив.

6. **Bot API не умеет файлы > 50MB.** Если планируешь грузить большие видео или базы данных в чат — Bot API не подойдёт. Альтернатива: положить на S3/R2 (Блок 6) и слать ссылку. OpenClaw умеет дробить только в рамках одного сообщения, не превышать общий лимит.

7. **Forum Topics: `threadId=1` — это General.** Для General НЕ передавать `message_thread_id` в sendMessage — Telegram вернёт `Bad Request: message thread not found`. OpenClaw это обрабатывает автоматически, но если делаешь руками — учитывай.

8. **Запуск двух поллеров с одним токеном = катастрофа.** OpenClaw запрещает второго поллера на тот же токен. Если у тебя dev и prod на одной машине — токены должны быть РАЗНЫЕ (создай dev-бота отдельно). Иначе один поллер «крадёт» сообщения у другого.

9. **Telegram Premium для бота — не существует.** Telegram Premium только для пользователей. Для ботов есть «paid broadcasts» в BotFather (повышает лимит broadcast до 1000 msg/sec), но это платно и нужно только если у тебя десятки тысяч подписчиков. Для личного агента — не актуально.

10. **Не коммить `openclaw.json` с токеном.** Регулярно проверяй `git log -p | grep -i "bot.*token"`. Если случайно закоммитил — токен скомпрометирован, ИДИ в @BotFather → /token → /revoke и получай новый. Старый перестанет работать.

---

## Чек-лист выполнения

- [ ] Бот создан через @BotFather, токен сохранён в менеджер паролей
- [ ] В BotFather: Privacy Mode = ENABLED, Allow Groups = ON, Inline = OFF, Payments = OFF
- [ ] Display name и username установлены (про-тип: username должен быть осмысленным, потом не сменишь)
- [ ] Команды через `/setcommands` прописаны (start, status, help, mode)
- [ ] Токен лежит в `~/.openclaw/secrets/telegram_main.token` с `chmod 600`
- [ ] В `openclaw.json` указан `tokenFile` (НЕ `botToken` plaintext)
- [ ] `.gitignore` содержит `secrets/`, `*.token`, `openclaw.json`
- [ ] Numeric user_id Дмитрия получен через `getUpdates` (записан в безопасное место)
- [ ] OpenClaw запущен с `dmPolicy: "pairing"` (первичная настройка)
- [ ] `openclaw pairing list telegram` показывает запрос
- [ ] `openclaw pairing approve telegram <CODE>` отработал
- [ ] Конфиг переключён на `dmPolicy: "allowlist"` с `allowFrom: ["123456789"]`
- [ ] OpenClaw перезапущен, конфиг прошёл валидацию (`openclaw doctor`)
- [ ] Создана Forum Supergroup для Блока 16 (можно пустая, на будущее)
- [ ] Бот добавлен в супергруппу как админ с правом «Manage Topics»

---

## Верификация

### Hello World тест
1. С телефона Дмитрия (с аккаунта numeric ID 123456789) отправь боту: «Привет, кто ты?»
2. Ожидаемый ответ: что-то типа «Привет, я твой OpenClaw агент. Готов к работе.»
3. Если бот отвечает — DM allowlist работает.

### Контр-тест (САМЫЙ ВАЖНЫЙ)
1. Найди второй Telegram-аккаунт: жены, друга, или зарегистрируй ещё один на запасной номер.
2. С этого аккаунта отправь твоему боту любое сообщение.
3. Ожидаемый результат: **полная тишина**. Бот не отвечает, в логах OpenClaw запись «rejected DM from non-allowlisted sender».
4. Если бот ответил — критическая дыра, проверь конфиг.

### Voice-note тест (опционально, если планируешь Блок 20)
1. Отправь боту голосовое сообщение «Привет тест».
2. Ожидаемый: в логах OpenClaw видно запись о voice-note с пометкой `untrusted_text`. Транскрипция через Whisper подключится в Блоке 20 — пока agent её просто увидит как текст.

### Forum Supergroup тест (опционально)
1. В супергруппе в General топике напиши `@dmitriy_opus_assistant_bot привет`.
2. Бот должен ответить (если добавлен админом, и `requireMention` соблюдён).
3. Создай новый топик «Тест-агент-2», в `openclaw.json` добавь его `agentId`.
4. В нём agent должен отвечать как другой персонаж/контекст.

### Команда `openclaw doctor`
```bash
openclaw doctor
# Должно быть:
# ✓ Telegram channel: enabled
# ✓ Token: loaded from file
# ✓ DM policy: allowlist (1 entry)
# ✓ Group policy: allowlist (1 entry)
# ✓ Polling: active, last update 5s ago
```

---

## Реальная оценка времени

| Подзадача | Минут |
|-----------|-------|
| Создание бота в @BotFather (включая выбор имени) | 4 |
| Настройки Privacy/Groups/Inline/Commands | 4 |
| Получение numeric user_id (через getUpdates) | 3 |
| Создание `~/.openclaw/secrets/`, помещение токена | 3 |
| Правка `openclaw.json` (pairing вариант) | 4 |
| Запуск OpenClaw, первый pairing flow | 5 |
| Переключение на allowlist + перезапуск | 3 |
| Hello World тест | 1 |
| Контр-тест с другого аккаунта | 3 |
| Создание Forum Supergroup (опционально) | 5 |
| **Итого реалистично** | **30-35 минут** |

Если опытный — 20 мин. Если первый раз с BotFather и OpenClaw — закладывай 45 мин из-за залипаний на «а где этот пункт меню».

---

## Связи с другими блоками

**ДО:**
- **Блок 1 (VPS-фундамент)** — нужна работающая машина с OpenClaw. Без неё бота некуда подключать.
- **Блок 2 (Установка OpenClaw)** — конфиг `~/.openclaw/openclaw.json` должен существовать и валидироваться.
- **Блок 11 (Безопасность секретов)** — обязательно для безопасного хранения токена. tokenFile с chmod 600, секреты не в git.

**ПОСЛЕ:**
- **Блок 5 (Личность)** — после Telegram-канала следующий шаг: дать агенту голос/характер. Все ответы будут идти через этого бота.
- **Блок 16 (Мульти-агенты)** — Forum Supergroup, созданная сейчас, — фундамент. Каждый топик = один агент с разным `agentId`.
- **Блок 20 (Голос)** — голосовые сообщения через Whisper transcription + ElevenLabs TTS. Тег `[[audio_as_voice]]` будет использоваться из этого блока.
- **Блок 13 (Дашборд)** — мониторинг rate-limits, количества входящих/исходящих сообщений, отказов по allowlist.
- **Блок 14 (Git workflow)** — конфиг `openclaw.json` ОБЯЗАТЕЛЬНО в `.gitignore`. Если будешь версионировать — только пример без секретов.

**Резервные каналы (на случай блокировки Telegram в РФ):**
- Discord — open-source бот через Discord.js, аналогичная схема. Подключение в OpenClaw тоже через `channels.discord`.
- Signal — прайваси-альтернатива, но Bot API там сильно беднее.
- iMessage — только если на macOS, через Apple-only трюки. Не масштабируется.
- Хороший паттерн: Telegram (основной) + Discord (резервный) на один и тот же OpenClaw, оба разрешают только твой ID.

---

## Источники

- [OpenClaw — Telegram channel docs](https://docs.openclaw.ai/channels/telegram) — официальная документация по конфигурации каналу.
- [OpenClaw — Pairing docs](https://docs.openclaw.ai/channels/pairing) — детали pairing-flow, время жизни кодов, security model.
- [OpenClaw GitHub — telegram.md](https://github.com/openclaw/openclaw/blob/main/docs/channels/telegram.md) — voice-notes, mediaMaxMb, forum topics.
- [Telegram Bot API Changelog](https://core.telegram.org/bots/api-changelog) — версии 9.0-9.6 (апрель 2025 — апрель 2026).
- [Telegram Bot API основной reference](https://core.telegram.org/bots/api) — методы, типы, лимиты.
- [Telegram Bots FAQ](https://core.telegram.org/bots/faq) — Privacy Mode, rate limits, ограничения.
- [Telegram Stars + Payments](https://core.telegram.org/bots/payments-stars) — для будущей монетизации (XTR currency).
- [Telegram Mini Apps](https://core.telegram.org/bots/webapps) — Bot API 8.0 features.
- [BotNews канал](https://t.me/s/botnews) — официальные анонсы новых версий API от команды Telegram.
- [grammY rate limits guide](https://grammy.dev/advanced/flood) — практический справочник по флуд-лимитам.
- [Stack Junkie — OpenClaw pairing fix](https://www.stack-junkie.com/blog/openclaw-pairing-explained) — траблшутинг pairing.
- [Medium — Mikhel V Kuttickal: OpenClaw on Hostinger](https://medium.com/@mikhela65/how-to-connect-telegram-to-openclaw-on-hostinger-vps-control-your-ai-agent-from-anywhere-532ab7003d0e) — практическая статья для VPS.
- Issue #65690 в openclaw/openclaw — багрепорт про pairing loop после 2026.4.8 (если столкнёшься — это known issue).

