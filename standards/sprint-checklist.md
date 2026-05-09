# Sprint Readiness Checklist — все воркшопы

> Единый чек-лист для приёмщика-бота, аудиторов и участников.
> Каждый пункт — атомарный, с уровнем важности и командой проверки.

## Уровни важности

- ❗ **Критично** — без этого воркшоп НЕ пройден
- ⚠️ **Рекомендуется** — желательно, но не блокер
- 💡 **Опционально** — фичи на будущее, для продвинутых

## Сводка по воркшопам

| Воркшоп | Цель | Критичных (❗) | Всего пунктов | Время |
|---|---|---|---|---|
| W0 | Подготовка до старта | 11 | 18 | 30–60 мин |
| W1 | Установка + базовый бот | 28 | 47 | 90 мин |
| W2 | Память + контекст-защита | 14 | 24 | 90 мин |
| W3 | Проактивность + Skills | 11 | 21 | 90 мин |
| W4 | Multi-agent + n8n | 10 | 19 | 90 мин |
| W5 | Расширения + Mode of God | 7 | 17 | свободно |
| **Итог выпускник** | Полный цифровой сотрудник | **81** | **146** | **6–8 ч + время** |

---

# W0 — ПОДГОТОВКА (до старта Воркшопа 1)

> Cобираем «корзину» — VPS, ключи, Telegram, Antigravity. Без интернет-провайдера не приступаем.

## W0.A — VPS оплачен и доступен

- [ ] **W0.A.1** ❗ VPS оплачен у одного из топ-3 хостеров (Hetzner / Timeweb / Beget)
- [ ] **W0.A.2** ❗ Спецификация: **4 vCPU / 8 GB RAM / 30+ GB SSD** (на 2 vCPU бот тормозит 30–50 сек — мучение)
- [ ] **W0.A.3** ❗ ОС: **Ubuntu 24.04 LTS**
- [ ] **W0.A.4** ❗ Виртуализация: **KVM** (НЕ OpenVZ — ломает swap)
- [ ] **W0.A.5** ❗ IP-адрес и root-пароль пришли на email
- [ ] **W0.A.6** ⚠️ Datacenter в Европе или Москве (близко к участнику для SSH)

## W0.B — API-ключи получены и сохранены

- [ ] **W0.B.1** ❗ MiniMax — Coding Plan $10/мес активирован, ключ в безопасном месте
- [ ] **W0.B.2** ❗ DeepSeek — депозит $5+, API key получен
- [ ] **W0.B.3** ❗ OpenRouter — депозит $5+, API key получен, **Spending Limit $30/мес выставлен** в Settings
- [ ] **W0.B.4** ❗ Groq — бесплатный API key получен (для Whisper)
- [ ] **W0.B.5** ⚠️ OpenAI — депозит $5+, API key (для TTS-голоса)

## W0.C — Telegram-бот создан

- [ ] **W0.C.1** ❗ Через @BotFather создан бот, имя и username сохранены
- [ ] **W0.C.2** ❗ TELEGRAM_BOT_TOKEN сохранён
- [ ] **W0.C.3** ❗ TELEGRAM_USER_ID получен через @userinfobot
- [ ] **W0.C.4** ⚠️ Privacy mode включён в @BotFather → Bot Settings

## W0.D — Antigravity / Mac Terminal

- [ ] **W0.D.1** ❗ Antigravity установлена и аккаунт подключён
- [ ] **W0.D.2** ❗ Mac Terminal или iTerm2 открывается, понимает базовые `ssh`/`ls`
- [ ] **W0.D.3** ⚠️ В Antigravity открыта пустая папка под спринт (Командос / sprint / любая)

---

# W1 — УСТАНОВКА + БАЗОВЫЙ БОТ (90 минут)

> Цель: голый VPS превращается в OpenClaw daemon с Telegram-ботом, который отвечает голосом и рисует.

## W1.A — VPS hardening

- [ ] **W1.A.1** ❗ Ubuntu 24.04 — `lsb_release -d`
- [ ] **W1.A.2** ❗ Юзер `clawd` создан — `id clawd`
- [ ] **W1.A.3** ❗ Passwordless sudo — `ssh clawd@VPS "sudo -n whoami"` → `root`
- [ ] **W1.A.4** ❗ Root SSH заблокирован — `grep 'PermitRootLogin' /etc/ssh/sshd_config` → `no`
- [ ] **W1.A.5** ❗ ufw active с rate-limit — `sudo ufw status` показывает `22/tcp LIMIT`
- [ ] **W1.A.6** ❗ fail2ban active — `systemctl is-active fail2ban` → `active`
- [ ] **W1.A.7** ❗ Swap 4 GB — `swapon --show` показывает `/swapfile 4G`
- [ ] **W1.A.8** ❗ Node.js v22.X через nvm под clawd — `node -v` → `v22.x.y`
- [ ] **W1.A.9** ❗ loginctl Linger=yes — `loginctl show-user clawd | grep Linger` → `Linger=yes`
- [ ] **W1.A.10** ⚠️ unattended-upgrades с `Automatic-Reboot=false`
- [ ] **W1.A.11** 💡 SSH `ServerAliveInterval` 60 в `~/.ssh/config` участника (защита от idle timeout)

## W1.B — OpenClaw daemon

- [ ] **W1.B.1** ❗ npm установлен под clawd (НЕ root) — `which openclaw` → `/home/clawd/.npm-global/bin/openclaw`
- [ ] **W1.B.2** ❗ systemd-user `openclaw-gateway.service` active — `systemctl --user is-active openclaw-gateway`
- [ ] **W1.B.3** ❗ Gateway на 127.0.0.1:18789 (НЕ 0.0.0.0!) — `ss -tlnp | grep 18789` → `127.0.0.1`
- [ ] **W1.B.4** ❗ `openclaw doctor --deep` → 0 critical errors
- [ ] **W1.B.5** ❗ Daemon переживает logout (linger проверен в W1.A.9)
- [ ] **W1.B.6** ⚠️ Auto-restart on failure — `Restart=always` в unit-файле
- [ ] **W1.B.7** ❗ `npm i -g grammy` выполнен (известный баг 2026.4.29 — пакет не ставится автоматически)
- [ ] **W1.B.8** ⚠️ `plugins.allow` whitelist на 8 плагинов (вместо 70 → старт 18s → 2s)

## W1.C — Каскад моделей

- [ ] **W1.C.1** ❗ 5 auth profiles (`openclaw auth list` показывает minimax, deepseek, openrouter, groq, openai)
- [ ] **W1.C.2** ❗ `missingProvidersInUse` пусто
- [ ] **W1.C.3** ❗ Primary geo-aware: `minimax/MiniMax-M2.7` (Asia VPS) ИЛИ `deepseek/deepseek-v4-flash` (Europe/RU VPS) — slug case-sensitive!
- [ ] **W1.C.4** ❗ Fallback на primary: только дешевле primary (правило защиты от $4200/63h)
- [ ] **W1.C.5** ⚠️ Heartbeat: `openrouter/google/gemini-2.5-flash-lite`, every 60m
- [ ] **W1.C.6** ⚠️ Subagents: `openrouter/moonshotai/kimi-k2.6`
- [ ] **W1.C.7** ❗ Alias `premium`: `deepseek/deepseek-v4-pro`
- [ ] **W1.C.8** ⚠️ Alias `think`: `deepseek/deepseek-v4-pro:thinking`
- [ ] **W1.C.9** ⚠️ Probe primary зелёный — `openclaw models status` показывает `primary OK`
- [ ] **W1.C.10** ❗ В реальном ответе боту модель = primary slug (НЕ deepseek-flash как fallback!)

## W1.D — Telegram-бот

- [ ] **W1.D.1** ❗ Telegram channel active — `openclaw channels list` показывает `telegram active`
- [ ] **W1.D.2** ❗ `dmPolicy: allowlist` (НЕ pairing — QuickStart режим скипает вопрос, чинить руками)
- [ ] **W1.D.3** ❗ `allowFrom` содержит ЧИСЛОВОЙ user_id (не username)
- [ ] **W1.D.4** ❗ Token-файл с `chmod 600`
- [ ] **W1.D.5** ❗ Bot валиден — `getMe → ok:true`
- [ ] **W1.D.6** ❗ На «привет» бот отвечает за **≤5 секунд** (нормативно — для geo-fit)
- [ ] **W1.D.7** ⚠️ В ответе есть имя сотрудника из SOUL.md

## W1.E — Картинки

- [ ] **W1.E.1** ❗ `tools.profile = "full"` (без этого `/image` не работает)
- [ ] **W1.E.2** ⚠️ Image default: `openrouter/google/gemini-2.5-flash-image`
- [ ] **W1.E.3** ⚠️ Image fast: `openrouter/black-forest-labs/flux-schnell`
- [ ] **W1.E.4** ⚠️ `/image кот` возвращает картинку за 5–15 сек
- [ ] **W1.E.5** ⚠️ Стоимость одной картинки ≤ $0.05

## W1.F — Защита от runaway

- [ ] **W1.F.1** ❗ Watchdog cron установлен — `crontab -l` показывает `*/30 * * * * watchdog.sh`
- [ ] **W1.F.2** ❗ Скрипт `~/.openclaw/scripts/watchdog.sh` существует с **`chmod 700`** (cron нужен +x)
- [ ] **W1.F.3** ❗ В watchdog.sh реальные `TG_TOKEN` и `TG_USER_ID` (НЕ переменные в кавычках)
- [ ] **W1.F.4** ⚠️ Watchdog тест-запуск `bash watchdog.sh` → `exit 0`
- [ ] **W1.F.5** ❗ OpenRouter Spending Limit $30/мес установлен в Settings
- [ ] **W1.F.6** 💡 Config-level `spending.caps` (если поддержит будущая версия — сейчас НЕ применяется в 2026.4.29)
- [ ] **W1.F.7** 💡 `premiumGuard` (НЕ применяется в 2026.4.29 — полагаемся на SOUL.md правило)

## W1.G — Голос (опционально, но добавляет 80% «вау»)

- [ ] **W1.G.1** ⚠️ TTS настроен: `openai tts-1` голос `alloy`, `maxLen 200`
- [ ] **W1.G.2** ⚠️ На короткое сообщение бот отвечает голосом
- [ ] **W1.G.3** 💡 Whisper транскрипция входящих голосовых через Groq
- [ ] **W1.G.4** 💡 Бот понимает голосовое в режиме команды (например голосовое `/image`)

## W1.H — UX и чистота

- [ ] **W1.H.1** ⚠️ Бот не показывает «Working...» / `sessions_yield` в Telegram
- [ ] **W1.H.2** ⚠️ Бот не показывает chain-of-thought (`<thinking>...`)
- [ ] **W1.H.3** ⚠️ SOUL.md содержит anti-sycophancy правило (нет «Отличный вопрос!»)
- [ ] **W1.H.4** 💡 SOUL.md/USER.md/IDENTITY.md собраны через интервью (9 вопросов)

## W1.I — Сдача (Шаги домашки 1–5)

- [ ] **W1.I.1** ❗ Голосовое отправлено и получен голосовой ответ (или текстовый с пометкой)
- [ ] **W1.I.2** ❗ `/image [своя тема]` сгенерил картинку
- [ ] **W1.I.3** ❗ `/premium` диалог-интервью (5 вопросов от бота → план)
- [ ] **W1.I.4** ❗ Самопрезентация (дерзкая, с провокационным вопросом)
- [ ] **W1.I.5** ❗ Аудитор выдал **🎉 ВОРКШОП 1 ПРОЙДЕН** (зелёный вердикт)
- [ ] **W1.I.6** ❗ Все 5 артефактов отправлены спринт-боту

---

# W2 — ПАМЯТЬ + КОНТЕКСТ-ЗАЩИТА (90 минут)

> Цель: бот помнит разговоры между сессиями. Контекст не раздувается. Cross-session retrieval работает.

## W2.A — Хранилище памяти

- [ ] **W2.A.1** ❗ Qdrant в Docker — `docker ps | grep qdrant` → running на 6333
- [ ] **W2.A.2** ❗ `~/.openclaw/memory/` существует, права `750`
- [ ] **W2.A.3** ⚠️ Daily logs шаблон `_templates/daily.md`, append-only

## W2.B — Embeddings + retrieval

- [ ] **W2.B.1** ❗ Embedding-модель настроена: `text-embedding-3-small` (OpenAI) или `bge-m3` (локально)
- [ ] **W2.B.2** ❗ Hybrid search включён (vectors + BM25)
- [ ] **W2.B.3** ⚠️ Reranker подключён (Cohere v3 или локальный `bge-reranker-v2-m3`)
- [ ] **W2.B.4** ⚠️ `temporalDecay` настроен: half-life 14 дней
- [ ] **W2.B.5** ⚠️ MMR динамический: `λ=0.7+` для entity-вопросов, `0.5` для общих

## W2.C — Compaction (защита от раздувания контекста)

- [ ] **W2.C.1** ❗ `memory.compaction.softThresholdTokens: 40000` — сжатие при достижении
- [ ] **W2.C.2** ❗ `hardThresholdTokens: 80000` — жёсткий потолок
- [ ] **W2.C.3** ❗ `strategy: "summarize-middle"` — режет середину, не голову/хвост
- [ ] **W2.C.4** ⚠️ `summarizerModel: "claude-haiku-4-5"` — дёшево
- [ ] **W2.C.5** ⚠️ `preserveTags: [decision, fact, action-required]` — критическое не сжимается

## W2.D — Pre-compaction memory flush

- [ ] **W2.D.1** ⚠️ `agents.defaults.compaction.memoryFlush.enabled: true`
- [ ] **W2.D.2** ⚠️ `softThresholdTokens: 4000` для flush'а
- [ ] **W2.D.3** ⚠️ `model: "anthropic/claude-haiku-4-6"` — дёшево
- [ ] **W2.D.4** 💡 issue #54408 мониторинг — flush не «протекает» в основную сессию

## W2.E — Continuation-skip + bootstrap caps

- [ ] **W2.E.1** ⚠️ `agents.defaults.contextInjection: "continuation-skip"` (экономия 8–12k токенов)
- [ ] **W2.E.2** ✅ `bootstrapMaxChars: 12000` (дефолт работает)
- [ ] **W2.E.3** ✅ `bootstrapTotalMaxChars: 60000` (дефолт работает)

## W2.F — Privacy guard

- [ ] **W2.F.1** ❗ `detect-secrets` v1.5+ установлен
- [ ] **W2.F.2** ❗ `blockOnDetect: true` — пароли/токены НЕ пишутся в memory
- [ ] **W2.F.3** ⚠️ Кастомные паттерны для рос. реалий (СНИЛС, ИНН, BIN-карт)

## W2.G — Daily logs + weekly digest

- [ ] **W2.G.1** ⚠️ `memory/2026-MM-DD.md` пишется автоматически append-only
- [ ] **W2.G.2** ⚠️ Cron `weekly-digest` понедельник 08:00 — суммари 7 daily-logs
- [ ] **W2.G.3** 💡 Forgetting policies: tag `daily` 90 дней, `ephemeral` 14 дней

## W2.H — Сдача (Amnesia test)

- [ ] **W2.H.1** ❗ После `/reset` бот помнит что «Иван — CTO Acme, бюджет $50k» (из прошлой сессии)
- [ ] **W2.H.2** ❗ `bash tests/amnesia.sh` → PASS
- [ ] **W2.H.3** ⚠️ `openclaw memory stats` показывает текущий tokens, soft threshold

---

# W3 — ПРОАКТИВНОСТЬ + SKILLS (90 минут)

> Цель: бот сам начинает разговоры. Утренний брифинг, вечерний дайджест. Skills из ClawHub.

## W3.A — Heartbeat (cron-голос бота)

- [ ] **W3.A.1** ❗ `heartbeat.enabled: true` в openclaw.json
- [ ] **W3.A.2** ❗ `heartbeat.model: openrouter/google/gemini-2.5-flash-lite` (дёшево, 60m)
- [ ] **W3.A.3** ⚠️ `wake-mode: batch` — несколько событий за 1 turn
- [ ] **W3.A.4** ⚠️ `isolated-session: true` — не засоряет основной диалог

## W3.B — Cron-сценарии

- [ ] **W3.B.1** ❗ Утренний брифинг — `cron 08:00 * * * *`, активирует heartbeat
- [ ] **W3.B.2** ⚠️ Вечерний дайджест — `cron 21:00 * * * *`
- [ ] **W3.B.3** ⚠️ HEARTBEAT.md содержит триггеры: «при утре спроси что планируется», «при вечере подведи итоги»
- [ ] **W3.B.4** 💡 Random check-in 1 раз в неделю в случайное время

## W3.C — Skills из ClawHub

- [ ] **W3.C.1** ⚠️ `openclaw skills list --installed` показывает минимум 3 скилла
- [ ] **W3.C.2** ⚠️ `google-calendar` skill подключён, OAuth flow прошёл
- [ ] **W3.C.3** ⚠️ `gmail` skill подключён (read-only mode для безопасности)
- [ ] **W3.C.4** 💡 `obsidian-sync` skill подключён, vault путь настроен
- [ ] **W3.C.5** 💡 `qmd-external` skill для Markdown-обмена

## W3.D — Tools

- [ ] **W3.D.1** ❗ `tools.fs` — read/write на `~/.openclaw/workspace/` разрешён
- [ ] **W3.D.2** ⚠️ `tools.exec.ask: per-command` — каждая bash-команда требует подтверждения
- [ ] **W3.D.3** ⚠️ `tools.web_search` через Brave Search API
- [ ] **W3.D.4** ⚠️ `tools.web_fetch` для загрузки страниц
- [ ] **W3.D.5** 💡 `tools.browser` (Playwright headless)

## W3.E — MCP-серверы

- [ ] **W3.E.1** ⚠️ Tavily MCP — `openclaw mcp list` показывает `tavily active`
- [ ] **W3.E.2** ⚠️ Notion MCP подключён (если NOTION_API_KEY есть)
- [ ] **W3.E.3** 💡 GitHub MCP подключён (если GITHUB_PAT есть)
- [ ] **W3.E.4** 💡 Playwright MCP

## W3.F — Сдача

- [ ] **W3.F.1** ❗ Бот сам прислал утренний брифинг в 08:00 (или в течение часа)
- [ ] **W3.F.2** ❗ Минимум 1 skill активно используется (например календарь подсказывает следующую встречу)
- [ ] **W3.F.3** ⚠️ `kb_search` через web_search возвращает свежие результаты

---

# W4 — MULTI-AGENT + N8N (90 минут)

> Цель: команда из 4 агентов (main/research/content/support). n8n для no-code автоматизации.

## W4.A — Мульти-агентная архитектура

- [ ] **W4.A.1** ❗ AGENTS.md содержит 4 ролевых агента: main, research, content, support
- [ ] **W4.A.2** ❗ `bindings` для каждого агента: какие tools/skills/каналы доступны
- [ ] **W4.A.3** ⚠️ `sessions_spawn` делегирует задачи между агентами
- [ ] **W4.A.4** ⚠️ Каждый агент имеет свой SOUL-фрагмент (тон/стиль)

## W4.B — Telegram Forum для мульти-агентов

- [ ] **W4.B.1** ⚠️ Telegram Forum Supergroup создан
- [ ] **W4.B.2** ⚠️ 4 топика — по одному на каждого агента
- [ ] **W4.B.3** ⚠️ `dmPolicy: allowlist` для всех топиков (тот же user_id)
- [ ] **W4.B.4** 💡 Topic-routing: упоминание `@research` маршрутизирует на research-агента

## W4.C — n8n в Docker

- [ ] **W4.C.1** ⚠️ n8n container running — `docker ps | grep n8n`
- [ ] **W4.C.2** ⚠️ n8n доступен через SSH-туннель на localhost:5678
- [ ] **W4.C.3** ⚠️ Минимум 1 workflow создан (например «нашёл новость → пост в Telegram»)

## W4.D — n8n ↔ OpenClaw integration

- [ ] **W4.D.1** ⚠️ `openclaw skills install n8n` — skill подключён
- [ ] **W4.D.2** ⚠️ Двусторонний trigger: бот может запустить n8n workflow и получить результат
- [ ] **W4.D.3** 💡 Webhook-receiver в OpenClaw для триггеров от n8n

## W4.E — Сдача

- [ ] **W4.E.1** ❗ В Forum-группе бот отвечает разными «голосами» в разных топиках
- [ ] **W4.E.2** ❗ n8n workflow реально запустился (видно в n8n executions log)
- [ ] **W4.E.3** ⚠️ Логи показывают `sessions_spawn` между агентами

---

# W5 — РАСШИРЕНИЯ + MODE OF GOD (свободно)

> Цель: Obsidian, мобильные ноды, Lobster, Smart Routing, локальный Whisper.

## W5.A — Obsidian sync

- [ ] **W5.A.1** ⚠️ Symlink `workspace/` и `memory/` → vault настроен
- [ ] **W5.A.2** ⚠️ QMD cross-indexing работает (поиск по vault через бота)
- [ ] **W5.A.3** 💡 Фаза 0 read-only — бот сначала только читает vault
- [ ] **W5.A.4** 💡 Конфликт с Obsidian Sync разрешён (одна сторона ведущая)

## W5.B — Мобильные ноды (Android/iOS)

- [ ] **W5.B.1** 💡 OpenClaw Node app установлен на телефон
- [ ] **W5.B.2** 💡 Tailscale connect VPS ↔ телефон работает
- [ ] **W5.B.3** 💡 Foreground service для battery optimization включён

## W5.C — Lobster (детерминированные YAML workflows)

- [ ] **W5.C.1** 💡 Lobster skill установлен
- [ ] **W5.C.2** 💡 Минимум 1 YAML-workflow с approval gate
- [ ] **W5.C.3** 💡 Пример workflow: «утром проверь почту → если важное — спроси разрешение → отправь summary»

## W5.D — Mode of God (Smart Routing + локальный Whisper + Memsearch)

- [ ] **W5.D.1** ⚠️ Smart Routing экономит ≥90% (router-модель решает куда отправить)
- [ ] **W5.D.2** ⚠️ Локальный Whisper через `faster-whisper` — транскрипция бесплатная
- [ ] **W5.D.3** 💡 Memory Injection — релевантные факты автоматически в каждый prompt
- [ ] **W5.D.4** 💡 Cognee Knowledge Graph подключён
- [ ] **W5.D.5** 💡 Memsearch UI работает локально

---

# 🎓 ВЫПУСКНИК СПРИНТА — итоговый чек-лист

> Если хотя бы половина пунктов ниже закрыта — у тебя полноценный AI-сотрудник.

## Базовый минимум (из всех ❗ предыдущих воркшопов)

- [ ] **GRAD.1** Бот отвечает в Telegram голосом и текстом
- [ ] **GRAD.2** Бот рисует картинки через `/image`
- [ ] **GRAD.3** Каскад моделей работает (primary + premium + heartbeat + subagents + image)
- [ ] **GRAD.4** Watchdog защита активна, $30/мес OpenRouter cap
- [ ] **GRAD.5** Бот помнит между сессиями (Qdrant + hybrid search)
- [ ] **GRAD.6** Compaction работает — длинные диалоги не съедают деньги
- [ ] **GRAD.7** Privacy guard блокирует утечки в memory
- [ ] **GRAD.8** Утренний брифинг приходит сам
- [ ] **GRAD.9** Минимум 1 skill активно используется (calendar / gmail / obsidian)
- [ ] **GRAD.10** Команда из 4 агентов в Forum-группе работает
- [ ] **GRAD.11** Минимум 1 n8n workflow подключён к боту

## Метрики

- [ ] **METRIC.1** Среднее время ответа ≤ 10 секунд
- [ ] **METRIC.2** Стоимость одного запроса ≤ $0.005
- [ ] **METRIC.3** Cache hit rate ≥ 60%
- [ ] **METRIC.4** Никаких runaway-инцидентов за месяц
- [ ] **METRIC.5** Бот переживает рестарт VPS без вмешательства

## Знания

- [ ] **KNOW.1** Понимаешь архитектуру: daemon ↔ gateway ↔ channels ↔ skills ↔ MCP
- [ ] **KNOW.2** Можешь сам добавить новый skill
- [ ] **KNOW.3** Можешь сам поправить SOUL.md
- [ ] **KNOW.4** Можешь сам диагностировать через `openclaw doctor --deep` и логи
- [ ] **KNOW.5** Знаешь куда смотреть в `~/.openclaw/` (workspace, memory, plugins, scripts)

---

## Использование чек-листа

### Для участника
- Открой свой воркшоп → пройди по ❗-пунктам → отметь чекбоксы
- Все ❗ закрыты → можно идти на следующий воркшоп
- ⚠️/💡 — улучшения, не блокируют

### Для приёмщика-бота
- Получает сдачу → парсит артефакты → проверяет соответствие пунктам ❗
- Если не все ❗ закрыты — отказ с указанием конкретного пункта (например «W1.D.6 — время ответа > 5 сек»)
- Если все ❗ закрыты — отметка «W{N} пройден» в state

### Для аудитора (Tab 03)
- Читает 8 артефактов из самопроверки
- Маппит каждый на пункт чек-листа
- Выдаёт таблицу «было / стало» по `❗ ❌` пунктам прошлой проверки

### Для Дмитрия
- Источник истины при дизайне следующего воркшопа
- Один файл — все воркшопы
- Можно git-diffить между когортами: что добавили, что убрали

---

## Связанные документы

- `workshop-1/guide.html` — интерактивный гайд для В1
- `workshop-1/04-homework.md` — финальная сдача В1
- `workshop-1/PENDING-FIXES-v1.8.md` — фиксы для следующей версии
- `standards/workshop-1-standard.md` — старый одно-воркшопный стандарт (заменяется этим файлом для В1)
- `knowledge-base/blocks/блок-XX-*.md` — глубокий ресерч по каждому блоку
- `knowledge-base/known-issues/*.md` — реальные баги и фиксы

## История изменений

- **2026-05-03** — создан единый чек-лист всех воркшопов (Дмитрий + Claude)
