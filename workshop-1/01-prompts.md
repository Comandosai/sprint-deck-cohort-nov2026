# 🎤 11 промптов Воркшопа 1

> Каждый промпт — короткий. AI сам определяет команды на основе стандарта.
> Перед началом убедись что ты вставил `00-meta-prompt.md` в чат с AI.

---

## Подставь СВОИ значения перед началом

Только в Промптах 3 и 4 нужны конкретные значения:

- `<VPS_IP>` → IP твоего VPS (на email от хостера)
- `<ROOT_PASSWORD>` → пароль root (на email от хостера)

В остальных промптах AI читает из `.env` — подставлять не нужно.

---

## 📦 Промпт 1 — Склонировать deck

```
Промпт 1: Склонируй наш deck с GitHub.
Репозиторий: https://github.com/Comandosai/sprint-deck-cohort-nov2026.git
В рабочую папку. Создай .env из .env.example.
```

---

## 🔑 Промпт 2 — SSH-ключ

```
Промпт 2: Создай мне SSH-ключ ed25519 в ~/.ssh/clawd_ed25519 без пароля.
Покажи публичный ключ.
```

---

## 🔑 Промпт 3 — Загрузить ключ на VPS

⚠️ **Замени** `<VPS_IP>` и `<ROOT_PASSWORD>` своими значениями ПЕРЕД вставкой:

```
Промпт 3: Загрузи мой публичный ключ на VPS.
VPS: <VPS_IP>
User: root
Пароль: <ROOT_PASSWORD>

После загрузки проверь что ssh -i ~/.ssh/clawd_ed25519 root@<VPS_IP> "echo OK"
работает БЕЗ пароля. Скажи «готово».
```

---

## ⚙️ Промпт 4 — Заполнить .env

⚠️ **Замени** `<VPS_IP>` своим значением ПЕРЕД вставкой:

```
Промпт 4: Отредактируй СУЩЕСТВУЮЩИЙ .env (не создавай новый!):
VPS_IP=<VPS_IP>
VPS_USER=root
SSH_KEY_PATH=~/.ssh/clawd_ed25519

Скажи мне «теперь вставь свои API-ключи в .env» — я их вставлю сам.
После моего «готово» проверь что в .env минимум 8 непустых строк VAR=значение.
```

---

## 🛡 Промпт 5 — Подготовить VPS

```
Промпт 5: Подготовь VPS по разделу A стандарта (standards/workshop-1-standard.md).
IP читай из .env.

КРИТИЧНО: passwordless sudo для clawd сделать ДО блокировки root!
Проверка перед блокировкой root: ssh clawd@VPS "sudo -n whoami" должен ответить root.

После завершения покажи какие критерии A.1-A.10 закрыл, и обнови мой .env: 
VPS_USER=root → VPS_USER=clawd.
```

---

## 🤖 Промпт 6 — Установить OpenClaw daemon

```
Промпт 6: Установи OpenClaw daemon на VPS под clawd по разделу B стандарта.
npm i -g БЕЗ sudo через npm prefix ~/.npm-global.
Gateway на 127.0.0.1, не 0.0.0.0!
systemd-user сервис с auto-restart, MemoryMax 2G.

Покажи что закрыл из B.1-B.6.
```

---

## 🧠 Промпт 7 — Каскад моделей

```
Промпт 7: Настрой каскад моделей по разделу C стандарта.

ВАЖНО:
- Primary: minimax/MiniMax-M2.7 (с заглавными буквами! case-sensitive!)
- Fallback: deepseek/deepseek-v4-flash (только дешевле primary!)
- Heartbeat: openrouter/google/gemini-2.5-flash-lite
- Subagents: openrouter/moonshotai/kimi-k2.6
- Alias premium: deepseek/deepseek-v4-pro
- Alias think: deepseek/deepseek-v4-pro:thinking

Эталонный config есть в config/openclaw.json — НО схема в установленной версии 
OpenClaw может отличаться, тогда настраивай через CLI команды (openclaw auth set, 
openclaw models set, fallbacks add, aliases set).

Ключи из .env подставляй прямыми значениями (set -a; source .env; set +a),
НЕ литералами.

После настройки проверь openclaw models status и openclaw auth list. 
В конце я напишу боту "привет" — должен ответить через MiniMax (НЕ через DeepSeek).
В логах модель = minimax/MiniMax-M2.7.

Если probe MiniMax падает — диагностируй причину (slug? endpoint? ключ?), не молчи.

Покажи что закрыл из C.1-C.10.
```

---

## 📱 Промпт 8 — Telegram-бот

```
Промпт 8: Подключи Telegram-бот по разделу D стандарта.
Токен и user_id из .env (TELEGRAM_BOT_TOKEN, TELEGRAM_USER_ID).
dmPolicy: allowlist, allowFrom: числовой user_id.
Token в файле с chmod 600 (НЕ в openclaw.json напрямую).

Спроси меня «как зовут твоего цифрового сотрудника?». 
После моего ответа — впиши имя в SOUL.md с правилом 
«не использовать пустые фразы вроде Отличный вопрос!».

После restart скажи мне «напиши боту привет в Telegram».

Когда я напишу — покажи логи и убедись что модель в логах = minimax/MiniMax-M2.7
(не deepseek!). Если deepseek — что-то с probe MiniMax, диагностируй.

Покажи что закрыл из D.1-D.7.
```

---

## 🛡 Промпт 9 — Watchdog cron

```
Промпт 9: Настрой watchdog kill-switch по разделу F стандарта.
Cron каждые 30 минут на VPS. Если spend > $3/час — стоп daemon + alert в Telegram.

В watchdog.sh подставь TG_TOKEN и TG_USER_ID прямыми значениями из .env 
(через set -a; source .env; set +a; затем подставить в heredoc).

Также напомни мне зайти на openrouter.ai и поставить Spending Limit $30/мес 
(уровень F.5). Это я делаю сам в браузере.

Покажи что закрыл из F.1-F.5.
```

---

## 🎨 Промпт 10 — Картинки

```
Промпт 10: Настрой генерацию картинок по разделу E стандарта.
Default: openrouter/google/gemini-2.5-flash-image
Fast: openrouter/black-forest-labs/flux-schnell

Проверь что tools.profile = "full" (НЕ messaging и НЕ coding!).
В SOUL.md добавь правило про команду /image.

После restart — я напишу боту "/image кот в шапке астронавта".
Должна прийти картинка за 5-15 сек. Покажи стоимость через openclaw spend.

Закрой E.1-E.5.
```

---

## ✅ Промпт 11 — Финальная самопроверка

```
Промпт 11: Сделай финальную самопроверку Воркшопа 1.

Пройдись по разделам A-G стандарта (standards/workshop-1-standard.md) и для 
каждого ❗ критерия выдай статус:
- ✅ закрыто (с доказательством — выводом команды)
- ⚠️ частично / неясно
- ❌ не закрыто (с объяснением почему)

В конце скажи общий вердикт:
- 🎉 «Воркшоп 1 пройден» — все ❗ закрыты
- ⚠️ «Почти готово» — есть мелкие ⚠️, но критичные ❗ закрыты
- ❌ «Есть проблемы» — что-то ❗ не закрыто

Сохрани отчёт самопроверки на VPS как ~/.openclaw/workshop-1-self-check.md
для последующего аудита.
```

---

# 🎯 После 11 промптов

После Промпта 11 у тебя должно быть:
- ✅ Бот в Telegram отвечает на «привет» через MiniMax
- ✅ `/image кот` возвращает картинку
- ✅ Watchdog в crontab
- ✅ Все ❗ критерии стандарта закрыты

**Дальше:**
1. Открой `02-self-check.md` — копируй 8 запросов в Telegram-бот, собирай артефакты
2. Открой `03-audit.md` — запусти независимый аудит в новом чате Antigravity

После аудита получишь окончательный вердикт «В1 пройден» или список доделок.
