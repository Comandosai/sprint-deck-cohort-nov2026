# 🎤 Воркшоп 1 — 11 промптов (гибридный путь)

> **AI делает 80% рутины, ты делаешь 1 ключевой шаг руками.**
> Перед началом убедись что вставил `00-meta-prompt.md` в чат с AI.

---

## 🧭 Структура воркшопа

```
ЧАСТЬ А1 — AI делает рутину (5 промптов, ~10 минут)
   П1. Склонировать deck + .env
   П2. SSH-ключ
   П3. Загрузить ключ на VPS
   П4. VPS hardening
   П5. Node 22 + npm + установить OpenClaw
   П6. СТОП — передаю эстафету тебе

   ⏸ ЧАСТЬ А2 — ТЫ САМ в Mac Terminal (~10 минут)
   ssh clawd@VPS_IP
   openclaw onboard   ← интерактивный мастер
   → бот отвечает в Telegram

ЧАСТЬ Б — AI доделывает тонкости (4 промпта, ~10 минут)
   П7. Alias premium / think
   П8. Watchdog
   П9. Картинки
   П10. SOUL.md (личность)
   П11. Финальная самопроверка
```

**Итого**: ~30 минут.

---

## 🟢 ПРЕД-ШАГ — Открой пустую папку в Antigravity (1 мин, ты сам)

ДО первого промпта подготовь рабочую папку:

1. **Создай новую пустую папку** в Finder (например `~/Desktop/Командос`)
2. В Antigravity: **File → Open Folder** → выбери эту папку
3. Убедись что в ней **ничего нет** кроме `.DS_Store` (если есть твои файлы — выбери другую пустую, иначе git clone упадёт)

Теперь Antigravity открыт на твоей рабочей папке. AI будет работать **прямо в ней**.

---

## 📦 ПРОМПТ 1 — Склонировать deck В ТЕКУЩУЮ ПАПКУ + .env

```
Промпт 1: Склонируй deck В МОЮ РАБОЧУЮ ПАПКУ (ту что открыта сейчас в Antigravity).

ШАГ 1 — узнай где мы:
  pwd
  ls -la

ШАГ 2 — клонируй ПРЯМО СЮДА (точка в конце критична!):
  rm -f .DS_Store
  git clone https://github.com/Comandosai/sprint-deck-cohort-nov2026.git .

  ⚠️ Точка в конце = клонировать в ТЕКУЩУЮ папку, не в подпапку.
  Если git ругается «destination path already exists and is not empty» —
  СТОП, спроси меня.

ШАГ 3 — проверь что файлы появились:
  ls -la
  Должно быть: README.md, AGENTS.md, .env.example, .gitignore, .git/,
  workshop-1/, knowledge-base/, standards/, config/, audit/, scripts/,
  checklists/, docs/, skills/, workspace/

ШАГ 4 — теперь ЧИТАЙ файлы:
  1. standards/workshop-1-standard.md — ИСТОЧНИК ИСТИНЫ.
     Прочитай ПОЛНОСТЬЮ. Запомни разделы A-H и критерии ❗/⚠️/💡.
  2. knowledge-base/README.md — индекс known-issues.
  3. config/openclaw.json — эталонный конфиг (для справки).

ШАГ 5 — создай .env:
  cp .env.example .env

ШАГ 6 — скажи мне:
  «вставь свои 9 значений в .env, файл лежит по пути [полный pwd]/.env»
  
  Я открою .env в Antigravity и впишу из Notes:
  VPS_IP, ROOT_PASSWORD, MINIMAX_API_KEY, DEEPSEEK_API_KEY,
  OPENROUTER_API_KEY, GROQ_API_KEY, OPENAI_API_KEY,
  TELEGRAM_BOT_TOKEN, TELEGRAM_USER_ID.

После моего «готово»:
- Проверь .env — минимум 9 непустых VAR=значение
- Покажи список ИМЁН переменных (БЕЗ значений!)
- Кратко (3-5 строк) перескажи ключевые ❗ критерии стандарта
- Скажи «контекст загружен, готов к Промпту 2 (SSH-ключ)»

⛔ ВАЖНО: ВСЁ В ТЕКУЩЕЙ ПАПКЕ.
НЕ создавай новую папку comandos-claw-deck где-то ещё.
НЕ делай cd ~/Desktop/что-то — работай В ТЕКУЩЕМ pwd.
```

---

## 🔑 ПРОМПТ 2 — SSH-ключ

```
Промпт 2: Создай SSH-ключ ed25519 в ~/.ssh/clawd_ed25519 БЕЗ пароля.

ssh-keygen -t ed25519 -f ~/.ssh/clawd_ed25519 -C "clawd@vps" -N ""

Покажи мне ПУБЛИЧНЫЙ ключ (содержимое clawd_ed25519.pub) — он понадобится в
следующем промпте.
```

---

## 🔌 ПРОМПТ 3 — Загрузить ключ на VPS

```
Промпт 3: Загрузи мой публичный SSH-ключ на VPS как root.

VPS_IP и ROOT_PASSWORD читай из .env через
`set -a; source .env; set +a`.

Если твой инструмент блокирует SSH с паролем (Codex/Claude Code часто блокируют)
— дай мне готовую команду для МОЕГО Mac Terminal:

  ssh-copy-id -i ~/.ssh/clawd_ed25519.pub root@<VPS_IP>

Я введу root-пароль сам и скажу «загрузил».

После моего «загрузил» проверь:
  ssh -i ~/.ssh/clawd_ed25519 -o BatchMode=yes root@<VPS_IP> "echo OK"

Должно ответить OK без пароля. Это закрывает A.4 (SSH key-based auth работает).
```

---

## 🛡 ПРОМПТ 4 — VPS hardening

```
Промпт 4: Подготовь VPS по разделу A стандарта (standards/workshop-1-standard.md).

Подключайся как root через ~/.ssh/clawd_ed25519. Выполни:

1. apt update && apt upgrade -y (без интерактива: DEBIAN_FRONTEND=noninteractive)
2. Создать пользователя clawd (--disabled-password, в группу sudo)
3. ⚠️ КРИТИЧНО: passwordless sudo для clawd ДО блокировки root:
   echo "clawd ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/clawd
   chmod 440 /etc/sudoers.d/clawd

   ОБЯЗАТЕЛЬНО проверь: su - clawd -c "sudo -n whoami" → должно ответить root.
   Если нет — СТОП, скажи мне, не блокируй root SSH!

4. Скопировать SSH-ключ из /root/.ssh/authorized_keys в /home/clawd/.ssh/
   (chmod 600, owner clawd:clawd)

5. Заблокировать root SSH:
   PermitRootLogin no
   PasswordAuthentication no
   systemctl restart ssh

6. ufw: deny incoming, allow outgoing, limit 22/tcp, enable

7. fail2ban: install, enable, start

8. Swap 4GB через /swapfile + /etc/fstab

9. unattended-upgrades + Automatic-Reboot=false

10. loginctl enable-linger clawd

После — обнови .env: VPS_USER=root → VPS_USER=clawd.

Покажи какие критерии A.1-A.10 закрыл.
```

---

## 📦 ПРОМПТ 5 — Node 22 + npm + OpenClaw

```
Промпт 5: Установи Node 22 + npm prefix + OpenClaw на VPS под clawd.

Подключайся как clawd через ssh -i ~/.ssh/clawd_ed25519.

1. nvm установка через https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh

2. nvm install 22 → nvm use 22 → nvm alias default 22

3. npm prefix:
   mkdir -p ~/.npm-global
   npm config set prefix '~/.npm-global'

4. ⚠️ PATH в ТРИ файла (это КРИТИЧНО для cron/systemd/non-login shell):
   echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc
   echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.profile
   echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bash_profile

5. npm i -g openclaw  (БЕЗ sudo)

Проверки через bash -lc:
- node --version → v22.x.x
- bash -lc "openclaw --version" → 2026.4.x
- bash -lc "which openclaw" → /home/clawd/.npm-global/bin/openclaw

⛔ ЗАПРЕЩЕНО: НЕ ЗАПУСКАЙ openclaw onboard! Это интерактивный TTY-мастер
для ЧЕЛОВЕКА. Через AI-batch вызовы он не работает корректно (мы это
проверили — упирается в pairing-ловушки на 2 дня).

Покажи что закрыл из B.1, B.5. Скажи: «openclaw установлен, готов к
ручному onboarding — делай Промпт 6».
```

---

## ⏸ ПРОМПТ 6 — СТОП. Эстафета человеку

```
Промпт 6: Стоп. Сейчас Я открою Mac Terminal и САМ пройду интерактивный
openclaw onboard. Это TTY-мастер, ты не справишься через batch.

Не делай больше ничего. Жди моё сообщение «бот живой в Telegram».

Когда я вернусь — дам Промпт 7 (alias premium и тонкие настройки).
```

---

# ⏸ ЧАСТЬ А2 — ТЫ САМ в терминале (10 минут)

> Подойдёт **любой полноценный терминал** (НЕ AI-плагин в Antigravity!):
> - 🟢 Antigravity Terminal (View → Terminal) — рекомендуется, в папке проекта
> - 🟡 Mac Terminal.app (Spotlight → Terminal)
> - 🔵 Windows: WSL / Git Bash
>
> ⚠️ Главное **НЕ путать**: AI-плагин Antigravity (Claude Code / Codex) не может запустить TTY-мастер. А **встроенный Terminal в Antigravity** (View → Terminal) — это обычный shell, в нём всё работает.

## 🔌 Подключись к VPS как clawd

Открой терминал **в папке проекта** (там где `.env`):
- 🟢 **Antigravity Terminal** (View → Terminal) — открывается уже в папке проекта, рекомендую
- 🟡 **Mac Terminal.app** — тогда сначала `cd` в папку проекта
- 🔵 **Windows: WSL / Git Bash** — команда работает идентично Mac

**Универсальная команда** (подставит VPS_IP автоматически из `.env`):

```bash
set -a && source .env && set +a && ssh -i ~/.ssh/clawd_ed25519 clawd@$VPS_IP
```

Что делает:
- `set -a && source .env && set +a` — подгружает переменные из `.env` в shell
- `$VPS_IP` — подставится автоматически (твой IP из `.env`)
- `~/.ssh/clawd_ed25519` — стандартный путь к ключу (создан в Промпте 2)
- `clawd` — стандартный юзер на VPS (создан в Промпте 4)

Должна открыться сессия `clawd@vps:~$` **без пароля**.

⚠️ Если получишь ошибку `Could not resolve hostname vps_ip` — значит ты в неправильной папке (нет `.env`) или `VPS_IP` пустой. Проверь: `pwd` (где ты) и `cat .env | grep VPS_IP` (есть ли значение).

## 🧙 Запусти мастер

```bash
openclaw onboard
```

## 📋 Cheat-sheet ответов на вопросы мастера

| # | Вопрос мастера | Ответ |
|---|---|---|
| 1 | Welcome / continue? | **Enter** |
| 2 | Mode? | **local** |
| 3 | Flow? | **quickstart** |
| 4 | **Authentication mode?** | **token** ⚠️ (НЕ skip!) |
| 5 | Gateway bind? | **loopback** |
| 6 | Gateway port? | **18789** или Enter |
| 7 | **Enable device-pair plugin?** | **yes** ⚠️ (если спросит — обязательно!) |
| 8 | Configure providers now? | **yes** |
| 9 | Add MiniMax? | **yes** → вставь `MINIMAX_API_KEY` |
| 10 | Add DeepSeek? | **yes** → вставь `DEEPSEEK_API_KEY` |
| 11 | Add OpenRouter? | **yes** → вставь `OPENROUTER_API_KEY` |
| 12 | Add Groq? | **yes** → вставь `GROQ_API_KEY` |
| 13 | Add OpenAI? | **yes** → вставь `OPENAI_API_KEY` |
| 14 | Default primary model? | **minimax/MiniMax-M2.7** ⚠️ (заглавные M!) |
| 15 | Configure channels? | **yes** |
| 16 | Channel type? | **telegram** |
| 17 | Telegram bot token? | вставь `TELEGRAM_BOT_TOKEN` |
| 18 | Channel name? | **main** или Enter |
| 19 | dmPolicy? | **allowlist** |
| 20 | Allow from user IDs? | твой `TELEGRAM_USER_ID` (числовой) |
| 21 | Install skills now? | **skip** (поставим в Воркшоп 3) |
| 22 | Install systemd-user service? | **yes** |
| 23 | Enable linger? | **yes** |
| 24 | Start daemon now? | **yes** |
| 25 | Run doctor? | **yes** |
| 26 | Save config? | **yes** |

**Если мастер задал вопрос которого нет в таблице** → нажми Ctrl+C, открой
консультанта (см. `knowledge-base/CONSULTANT-PROMPT.md`) и спроси что выбрать,
потом запусти `openclaw onboard` снова.

## ✅ Проверка после onboard

В той же SSH-сессии:

```bash
openclaw devices list           # должна быть запись с operator.admin
openclaw models status          # 5 провайдеров с ✓
openclaw channels list          # telegram main active
openclaw doctor --deep | tail   # 0 critical
systemctl --user status openclaw --no-pager | head -10
```

## 🤖 Напиши боту в Telegram

Открой Telegram → найди своего бота → напиши **«Привет!»**

Должно ответить за 3-5 сек. В SSH параллельно:
```bash
openclaw logs --since 30s
```

Найди строку `model=minimax/MiniMax-M2.7 ok` — победа.

⚠️ Если модель `deepseek` вместо `minimax` — fallback сработал, primary упал.
Скажи AI: «MiniMax не работает, в логах модель = deepseek. Диагностируй».

---

# 💚 Возвращайся в Antigravity

Скажи AI: **«бот живой, отвечает через MiniMax. Дай Промпт 7.»**

---

## 🎨 ПРОМПТ 7 — Alias premium и think

```
Промпт 7: Бот живой. Теперь добавь aliases для премиум-режима по разделу C
стандарта.

На VPS под clawd через bash -lc:

1. openclaw aliases set premium deepseek/deepseek-v4-pro
2. openclaw aliases set think deepseek/deepseek-v4-pro:thinking
3. openclaw aliases list  → должно показать оба

Также проверь:
- openclaw models status — primary minimax/MiniMax-M2.7
- Если fallback на primary не deepseek-v4-flash — добавь:
  openclaw fallbacks add minimax/MiniMax-M2.7 deepseek/deepseek-v4-flash

Закрой C.7, C.8.
```

---

## 🛡 ПРОМПТ 8 — Watchdog

```
Промпт 8: Настрой watchdog kill-switch по разделу F стандарта.

На VPS под clawd:

1. Создай ~/.openclaw/scripts/watchdog.sh с правами +x.
   ⚠️ ОБЯЗАТЕЛЬНО первой строкой ПОСЛЕ shebang:
     export PATH=$HOME/.npm-global/bin:$PATH
   Без этого cron не найдёт openclaw.

2. Логика watchdog: если за последний час расход > $3 — стоп daemon + alert
   в Telegram.

   TG_TOKEN и TG_USER_ID подставь ПРЯМЫМИ значениями из .env через
   `set -a; source ~/.env; set +a` heredoc.

3. crontab под clawd: */30 * * * * /home/clawd/.openclaw/scripts/watchdog.sh

4. Проверки:
   - crontab -l показывает строку
   - bash -lc "bash ~/.openclaw/scripts/watchdog.sh" → exit 0
   - chmod 700 на watchdog.sh (НЕ 600! Cron должен исполнить — execute-bit нужен)

Также напомни мне зайти на openrouter.ai → Settings → Spending Limit → $30/мес.

Закрой F.1-F.5.
```

---

## 🎨 ПРОМПТ 9 — Картинки

```
Промпт 9: Настрой генерацию картинок по разделу E стандарта.

Через bash -lc на VPS:

1. openclaw config set agents.defaults.imageGenerationModel.primary \
     openrouter/google/gemini-2.5-flash-image

2. openclaw config set agents.defaults.imageGenerationModel.fallbacks \
     '["openrouter/black-forest-labs/flux-schnell"]'

3. ⚠️ tools.profile ОБЯЗАТЕЛЬНО = "full" (стандарт E.1, не "messaging" и не "coding"!):
   bash -lc "openclaw config set tools.profile full"
   Иначе картинки могут не работать и провалится финальная самопроверка.

Перезапусти daemon:
  systemctl --user restart openclaw && sleep 5 && bash -lc "openclaw doctor --deep | tail -10"

После я напишу боту "/image кот в шапке астронавта" — покажи логи и подтверди
что картинка пришла.

Закрой E.1-E.5.
```

---

## 👤 ПРОМПТ 10 — SOUL.md (личность)

```
Промпт 10: Настрой личность бота через SOUL.md.

Спроси меня: «Как зовут твоего цифрового сотрудника? Какой у него характер
(дерзкий / тёплый / деловой / технарь)?»

После моего ответа создай ~/.openclaw/workspace/SOUL.md:

# Личность

## Имя
[имя]

## Характер
[характер]

## Правила
- Отвечай кратко и по делу на русском
- НИКОГДА не используй пустые фразы: «Отличный вопрос!», «С удовольствием
  помогу!», «Вот развёрнутый ответ:», «Конечно!»
- Не показывай chain-of-thought, не пиши «Анализирую...»
- Если не знаешь — скажи прямо «не знаю», не выдумывай

Перезапусти daemon. Я напишу боту «привет» — он должен представиться по имени
БЕЗ пустых фраз.

Закрой D.7, H.1-H.3.
```

---

## ✅ ПРОМПТ 11 — Финальная самопроверка

```
Промпт 11: Финальная самопроверка Воркшопа 1.

Пройдись по разделам A-H стандарта (standards/workshop-1-standard.md) и для
КАЖДОГО ❗ критерия выдай:
- ✅ закрыто (с доказательством — командой и её выводом)
- ⚠️ частично/неясно (с пояснением)
- ❌ не закрыто (с объяснением)

Обязательно покажи сырой вывод:
- bash -lc "openclaw devices list"
- bash -lc "openclaw models status"
- bash -lc "openclaw channels list"
- bash -lc "openclaw doctor --deep | tail -25"
- crontab -l
- systemctl --user status openclaw --no-pager | head -10

Сохрани отчёт самопроверки на VPS как ~/.openclaw/workshop-1-self-check.md
для последующего аудита.

Вердикт:
- 🎉 «Воркшоп 1 пройден» — все ❗ закрыты
- 🟡 «Почти готово» — все ❗ закрыты, есть ⚠️
- ❌ «Есть проблемы» — что-то ❗ не закрыто
```

---

# 🎯 После 11 промптов

После Промпта 11 у тебя должно быть:
- ✅ Бот в Telegram отвечает на «привет» через MiniMax M2.7
- ✅ `/image кот` возвращает картинку за 5-15 сек
- ✅ Бот представляется по имени
- ✅ Watchdog в crontab каждые 30 мин
- ✅ Все ❗ критерии стандарта закрыты

**Дальше:**
1. **`02-self-check.md`** — копируй 8 запросов прямо в Telegram-бот, собирай артефакты состояния
2. **`03-audit.md`** — запусти независимый аудит в НОВОМ чате Antigravity

После аудита получишь окончательный вердикт.

---

# 🆘 Если на любом промпте что-то падает

**Не паникуй и не лезь чинить через AI «попробуй ещё раз»** — это путь к двум дням ада.

Открой `knowledge-base/CONSULTANT-PROMPT.md`, скопируй его в **НОВЫЙ чат AI**
(не в этот!) — это твой персональный консультант с базой знаний 20 блоков
исследований + known-issues. Задай конкретный вопрос — получишь точный фикс
за 30 секунд.

Также см. `knowledge-base/known-issues/`:
- `1008-pairing-required.md` — gateway closed 1008
- `path-non-login-shell.md` — openclaw: command not found из cron
- `slug-case-sensitive.md` — minimax/minimax-m2.7 vs minimax/MiniMax-M2.7
- `device-pair-disabled.md` — paired.json пустой
- `runaway-4200-incident.md` — что не делать с fallback моделями
