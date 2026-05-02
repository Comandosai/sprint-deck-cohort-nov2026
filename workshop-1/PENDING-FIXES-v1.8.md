# 📋 Накопленные правки для v1.8 — план фиксов

> **Создан**: 2 мая 2026, после 4-часовой сессии прохождения гайда Дмитрием на VPS Timeweb (Москва).
>
> **Цель**: список всех правок которые надо внести в гайд по результатам реальной установки. Сохранён в репо как страховка от потери контекста чата.
>
> **Применить**: после того как у Дмитрия бот в Telegram заговорит.

---

## 🚨 Главное открытие сессии — geographic latency

VPS в Москве (RU) имеет RTT 162ms до MiniMax (Singapore), 7ms до DeepSeek (Cloudfront edge). Это **в 25 раз дальше** до MiniMax. В результате:
- `openclaw onboard` создаёт правильный pairing, но при первом сообщении в Telegram — **fetch-timeout** в 45 сек, не успевает auth + dispatch + stream.
- Bundled deps install (45 пакетов × N плагинов) забивает 2-CPU VPS на 95%, event loop тормозит на 18 сек.

**Стандарт C.3 («primary = minimax/MiniMax-M2.7»)** оказался **географически неверен** для не-Asia VPS. Для пользователей РФ/EU единственный рабочий вариант — DeepSeek primary.

---

## 🔧 ТЕХНИЧЕСКИЕ ФИКСЫ

### 1. `npm i -g grammy` в Промпт 5 (КРИТИЧНО!)

**Проблема**: OpenClaw 2026.4.29 имеет bug — bundled telegram-extension требует `grammy` runtime, но npm-пакет не объявлен в зависимостях. После `npm i -g openclaw` доктор показывает:
```
[channels] failed to load bundled channel telegram: Cannot find module 'grammy'
```
Бот в Telegram при этом не работает.

**Фикс в Промпте 5** (после `npm i -g openclaw`):
```bash
# Дополнительный шаг для bug в 2026.4.29:
bash -lc "npm i -g grammy"
```

### 2. `chmod 700` (НЕ 600) на watchdog.sh

✅ Уже зафиксировано в v1.7.0 в `01-prompts.md` Промпт 8 и в guide.html. Проверить что **в `knowledge-base/known-issues/06-runaway-4200-incident.md`** тоже корректно.

### 3. systemctl unit называется `openclaw-gateway.service` (НЕ `openclaw.service`)

В реальной установке OpenClaw 2026.4.29 systemd-user unit получает имя `openclaw-gateway.service`. Но в наших файлах (`01-prompts.md`, `guide.html`, `01a-install-by-hand.md`, `standards/workshop-1-standard.md`, все `known-issues/*.md`) везде пишется просто `openclaw.service`. Это вызывает ошибку:
```
Failed to restart openclaw.service: Unit openclaw.service not found.
```

**Фикс**: глобальная замена через find/sed:
```bash
find . -name "*.md" -o -name "*.html" | xargs grep -l "openclaw\.service" | grep -v openclaw-gateway
```
Заменить все упоминания `openclaw.service` → `openclaw-gateway.service` (кроме тех что уже `openclaw-gateway.service`).

Также `systemctl --user restart openclaw` → `systemctl --user restart openclaw-gateway`.

### 4. `tools.profile = "full"`

✅ Уже зафиксировано в v1.7.0 в Промпте 9. Проверить что нет рудиментов «messaging».

---

## 🧙 ИЗМЕНЕНИЯ В CHEAT-SHEET ONBOARD

OpenClaw 2026.4.29 имеет на 4-5 вопросов **больше** чем мы предполагали в исходном cheat-sheet (26 пунктов). Дополнить таблицу:

### Новые/изменённые пункты:

| # | Вопрос | Ответ | Примечание |
|---|---|---|---|
| **1a** | I understand this is personal-by-default and shared/multi-user use requires lock-down. Continue? | **Yes** (стрелка влево → Enter) | ⚠️ новый в 2026.4.29 |
| **2a** | Existing config detected → Config handling? | **Use existing values** | появляется при повторном запуске onboard |
| **9-13** | Add MiniMax/DeepSeek/etc?: расширить до **MiniMax auth method? → MiniMax API key (Global)** (НЕ CN, НЕ OAuth) | для первичной регистрации на platform.minimax.io |
| **14** | Default model? → выбрать **Keep current (minimax/MiniMax-M2.7)** | НЕ "Enter manually", НЕ "Browse all models" |
| **17** | Web search → Search provider? | **Skip for now** | веб-поиск настроим позже отдельно |
| **17a** | Skills status / Configure skills now? | **No** (skip) | skills в Воркшопе 3 |
| **17b** | Hooks → Enable hooks? | **Skip for now** | hooks потом |
| **18** | Health check failed: timeout? | **продолжать дальше** (info-панель) | gateway стартует асинхронно, доктор покажет позже |
| **19** | dmPolicy/allowFrom — ⚠️ **в QuickStart НЕ задаются** | пропускаются мастером | фиксим в Промпте 6.5 после onboard |
| **20** | (был «Allow from user IDs?») — нет в QuickStart | удалить из таблицы или пометить «не появляется» | см. выше |
| **21a** | Telegram already configured. What do you want to do? | **Skip (leave as-is)** | при повторном запуске onboard |
| **24** | **Hatch your bot? (КРИТИЧНО!)** | **Hatch in Terminal (recommended)** ⚠️ ⚠️ ⚠️ | **НЕ "Do this later"** — иначе scope upgrade не происходит, бот ловит 1008 для tool-calls |
| **25-28** | Workspace backup / Security / Shell completion / What now / Web search reminder | info-панели — просто Enter | финальные сообщения, ничего не делать |

### КРИТИЧНО про пункт 24

В onboarding 2026.4.29 после установки systemd сервиса появляется этот вопрос:
```
How do you want to hatch your bot?
● Hatch in Terminal (recommended)
○ Open the Web UI
○ Do this later
```

В сессии Дмитрий выбрал «Do this later» (мой совет был пропустить — оказалось неверно). В результате scope CLI остался только `operator.pairing`, не получил `operator.approvals` для tool-calls. Это привело к ошибке:
```
gateway closed (1008): pairing required: device is asking for more scopes than currently approved
```

**Правильный совет в гайде**: всегда **Hatch in Terminal (recommended)** — это первичный chat который активирует scope upgrade. Через TUI пройти короткий начальный диалог («My friend, please help me…»). Это часть бутстрапа, не пропускать.

---

## 🆕 НОВЫЙ ПРОМПТ 6.5 — «Tuning после onboard» (КРИТИЧНО!)

После того как `openclaw onboard` завершился, у пользователя оказывается **частично** настроенный бот. QuickStart режим скипает несколько важных вещей. Их нужно зафиксировать отдельным промптом.

### Промпт 6.5 содержание:

```
Промпт 6.5: Tuning после onboard. Закрываем дыры QuickStart режима.

На VPS под clawd через bash -lc:

ШАГ 1 — Закрыть бота от чужих (D.2 + D.3 стандарта):
  openclaw config set channels.telegram.dmPolicy "allowlist"
  openclaw config set channels.telegram.allowFrom '["TELEGRAM_USER_ID"]'
  
  Замени TELEGRAM_USER_ID на свой числовой user_id (читай из ~/.env).

ШАГ 2 — Назначить command owner для админ-команд бота:
  openclaw config set commands.ownerAllowFrom '["telegram:TELEGRAM_USER_ID"]'

ШАГ 3 — Включить plugins.allow whitelist (КРИТИЧНО для скорости!):
  По умолчанию активны 9-70 плагинов, каждый ставит 45 npm-пакетов на первом
  использовании. На 2-CPU VPS это забивает CPU на 95% и приводит к fetch-timeout.
  
  Через python:
  python3 <<EOF
  import json, shutil
  p = "/home/clawd/.openclaw/openclaw.json"
  shutil.copy(p, p + ".bak.before-tuning")
  c = json.load(open(p))
  c.setdefault("plugins", {}).setdefault("allow", [])
  c["plugins"].setdefault("entries", {})
  for prov in ["telegram","minimax","deepseek","openrouter","groq","openai","device-pair","memory-core"]:
      if prov not in c["plugins"]["allow"]:
          c["plugins"]["allow"].append(prov)
      c["plugins"]["entries"][prov] = {"enabled": True}
  json.dump(c, open(p,"w"), indent=2)
  print("plugins.allow:", c["plugins"]["allow"])
  EOF

ШАГ 4 — Поднять таймауты для slow networks:
  python3 <<EOF
  import json
  p = "/home/clawd/.openclaw/openclaw.json"
  c = json.load(open(p))
  c.setdefault("agents", {}).setdefault("defaults", {})["timeoutSeconds"] = 180
  c.setdefault("models", {}).setdefault("providers", {}).setdefault("minimax", {})["timeoutSeconds"] = 120
  json.dump(c, open(p,"w"), indent=2)
  print("timeouts: agents=180s, minimax=120s")
  EOF

ШАГ 5 — systemd override для Node ускорения:
  mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
  cat > ~/.config/systemd/user/openclaw-gateway.service.d/override.conf <<EOF
  [Service]
  Environment="OPENCLAW_NO_RESPAWN=1"
  Environment="NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache"
  EOF
  mkdir -p /var/tmp/openclaw-compile-cache
  systemctl --user daemon-reload

ШАГ 6 — Restart daemon + ожидание ready:
  systemctl --user restart openclaw-gateway && sleep 12
  journalctl --user -u openclaw-gateway --since "30 seconds ago" --no-pager | grep -E "ready|telegram.*provider" | tail -5

После этого Промпт 7 (каскад моделей) уже работает с быстрым стартом плагинов.

Закрой D.2, D.3 и снимаешь блокер «бот ловит fetch-timeout на первом сообщении».
```

---

## 🆕 НОВЫЙ ПРОМПТ 7 — geo-aware (универсальный для всей когорты)

**Цель**: один промпт который работает для VPS в любом регионе. AI измеряет ping до провайдеров и сам выбирает primary на основе RTT.

См. полный текст в чате выше (около сообщения «Промпт 7: Каскад моделей с учётом физики моего VPS (geo-aware)»). Содержание:
1. Auth profiles (5 провайдеров)
2. Ping до api.minimaxi.com / api.deepseek.com / api.openai.com
3. Auto-выбор primary по правилу: если RTT MiniMax ≤80ms → MiniMax (стандарт); иначе ближайший
4. Auto-fallback (только дешевле primary)
5. Aliases premium/think (всегда DeepSeek V4-Pro)
6. Все провайдеры в plugins.allow
7. Restart + проверки

**Заменить** старый Промпт 7 в `01-prompts.md` и `guide.html`.

---

## 🆕 НОВЫЕ KNOWN-ISSUES (3 файла)

### `knowledge-base/known-issues/08-slow-first-response.md`

**Симптом**: первое сообщение боту в Telegram отвечает 45+ секунд или ловит `fetch-timeout`. CPU на VPS забит на 95%.

**Причина**: каждый плагин (acpx, runway, tts-local-cli, talk-voice, browser, …) при первом активном использовании ставит свой комплект из 45 npm-пакетов. На 2-CPU VPS это занимает 18-20 секунд на плагин.

**Логи**:
```
[plugins] memory-core staging bundled runtime deps (45 specs): ...
[diagnostic] liveness warning: cpu utilization 0.955, eventLoopDelayMaxMs=18857
[telegram] sendChatAction failed: Network request failed
[fetch-timeout] fetch timeout reached; aborting operation
```

**Решение**:
1. Включить `plugins.allow` whitelist (только нужные плагины) — снижает старт с 18s до 2s
2. Поднять `agents.defaults.timeoutSeconds=180`
3. systemd env: `OPENCLAW_NO_RESPAWN=1` + `NODE_COMPILE_CACHE`

См. Промпт 6.5 (раздел выше).

### `knowledge-base/known-issues/09-geographic-latency.md`

**Симптом**: бот в Telegram отвечает через fallback (DeepSeek) вместо primary (MiniMax). В логах:
```
[fetch-timeout] fetch timeout reached; aborting operation
[FALLBACK] deepseek/deepseek-v4-flash
```

**Причина**: VPS физически далеко от MiniMax API (Singapore). Из EU/RU RTT 160ms+, MiniMax не успевает за дефолтные таймауты.

**Измерение**:
```bash
ping -c 3 api.minimaxi.com    # из Москвы: 162ms avg
ping -c 3 api.deepseek.com    # из Москвы: 6.7ms avg (Cloudfront edge)
```

**Решение**: переключить primary на DeepSeek для не-Asia VPS:
```bash
openclaw config set agents.defaults.model.primary deepseek/deepseek-v4-flash
openclaw fallbacks add deepseek/deepseek-v4-flash openai/gpt-4o-mini
```

**Альтернатива**: арендовать VPS в Singapore (DigitalOcean SGP1, Vultr SG, Linode SG) — но это переезд всего деплоя.

**Гайд по выбору primary по региону VPS**:
| Регион VPS | Primary | RTT |
|---|---|---|
| Asia (SG/HK/JP) | MiniMax M2.7 | 3-10ms |
| EU (Hetzner) | DeepSeek V4-Flash | 6-30ms |
| RU (Timeweb) | DeepSeek V4-Flash | 7ms |
| US | OpenAI/DeepSeek | 15-50ms |

### `knowledge-base/known-issues/10-hatch-skip-scope-issue.md`

**Симптом**: после onboard всё выглядит ок (paired device есть, models status работает), но при попытке tool-call в логах:
```
[telegram] connect error: scope upgrade pending approval
gateway closed (1008): pairing required: device is asking for more scopes than currently approved
```

В `openclaw devices list` у device scope = `operator.pairing` (не полный `operator.admin/pairing/read/write/approvals`).

**Причина**: на onboard в шаге «How do you want to hatch your bot?» был выбран **Do this later**. Этот шаг — TUI/dashboard chat для активации scope upgrade. Без него у CLI нет `operator.approvals`.

**Решение A (профилактика)**: всегда выбирать **Hatch in Terminal (recommended)** в onboard. Пройти короткий первичный диалог («Wake up, my friend!»).

**Решение B (если уже пропустил)**:
```bash
openclaw dashboard --no-open
```
В выводе будет URL вида `http://127.0.0.1:18789/#token=...`. Через SSH-туннель открыть в браузере на маке:
```bash
ssh -L 18789:127.0.0.1:18789 -i ~/.ssh/clawd_ed25519 clawd@VPS_IP
```
Открыть дашборд в браузере → нажать **Approve** на pending pairing-запросе → scope обновится до полного.

**Решение C (через CLI без браузера, экспериментально)**:
```bash
# Подсмотреть admin device token из paired.json
# Потом openclaw devices approve --latest --token <admin-token> --url ws://127.0.0.1:18789
```
(Этот путь работал в одной из сессий в прошлом, см. историю в `01-1008-pairing-required.md`).

---

## 📜 СТАНДАРТ — пересмотр C.3 и C.10

### C.3 (старая версия)
> Primary: `minimax/MiniMax-M2.7` (⚠️ slug case-sensitive! С заглавными!) ❗

### C.3 (новая версия)
> Primary выбирается на основе RTT с твоего VPS до провайдеров:
> - Если RTT до MiniMax ≤80ms → primary = `minimax/MiniMax-M2.7` ✅ (идеал)
> - Если RTT до MiniMax >80ms → primary = ближайший провайдер (обычно `deepseek/deepseek-v4-flash` для EU/RU)
>
> Это **физика**, не отступление от стандарта. Slug всегда case-sensitive.
> ❗ критично: primary должен **отвечать** на «привет» в Telegram за <15 сек.

### C.10 (старая)
> В реальном ответе боту в Telegram модель = `minimax/MiniMax-M2.7` (НЕ deepseek!)

### C.10 (новая)
> В реальном ответе боту модель = **выбранный** primary (НЕ fallback). Проверка через `openclaw logs --tail`.

---

## 🌍 ГЕОЛОКАЦИОННАЯ ТАБЛИЦА — добавить в Закладку 00 (Подготовка)

В разделе «A. VPS — где будет жить твой сотрудник» добавить блок:

### Какую модель ставить primary в зависимости от региона VPS

| 🌍 Регион VPS | 🎯 Рекомендуемый primary | RTT до провайдера | Почему |
|---|---|---|---|
| **Asia** (SG/HK/JP) | MiniMax M2.7 | 3-10ms | Идеально, MiniMax из Singapore |
| **EU** (Hetzner Frankfurt) | DeepSeek V4-Flash | 6-30ms | DeepSeek через Cloudfront edge |
| **RU** (Timeweb/Beget) | DeepSeek V4-Flash | 7ms | MiniMax в Singapore — 162ms |
| **US** (Vultr/DO) | OpenAI или DeepSeek | 15-50ms | Зависит от Cloudfront edge |

> 💡 **Не выбирай VPS специально под MiniMax** если у тебя ещё нет Asia VPS — DeepSeek V4-Flash на 90% задач закрывает потребность за $1-2/мес. Качество обоих моделей сравнимо.

---

## 🛡 PRE-FLIGHT в Промпте 4 (hardening)

После hardening (но до установки openclaw) добавить шаг:

```bash
echo "=== Latency check (для выбора primary в Промпте 7) ==="
ping -c 3 -W 2 api.minimaxi.com 2>&1 | tail -2
ping -c 3 -W 2 api.deepseek.com 2>&1 | tail -2
ping -c 3 -W 2 api.openai.com 2>&1 | tail -2
echo "=== Запомни эти значения — они нужны для Промпта 7 ==="
```

В отчёте о выполнении Промпта 4 AI должен:
- Показать таблицу RTT до 3 провайдеров
- Сказать: «На основе RTT для primary рекомендую: [provider]»

---

## 🎯 META-PROMPT — добавить блок «СТИЛЬ ОТВЕТОВ»

После блока «РЕЖИМЫ РАБОТЫ» добавить:

```
═══ СТИЛЬ ТВОИХ ОТВЕТОВ ═══

ЗОЛОТОЕ ПРАВИЛО: каждый твой ответ = ОДИН следующий шаг.
- 1 команда или 1 действие
- 1 ожидание («что должен увидеть»)
- 1 fallback («если упало — ЭТА команда диагностики»)

НЕ ДЕЛАЙ:
❌ Длинных «почему так и сяк» — теория не нужна
❌ Вариантов A/B/C на выбор — ВЫБЕРИ ЗА ПОЛЬЗОВАТЕЛЯ
❌ Технических терминов без перевода (если пишешь «scope» —
   добавь скобку «(права доступа)»)
❌ Перечислений длиннее 5 пунктов
❌ Стен текста с разборами полётов

ДЕЛАЙ:
✅ Одну конкретную команду — копи-паста готовая
✅ Простой русский — как объясняешь маме
✅ Точный ожидаемый результат
✅ Если ошибка — точный фикс (одна команда), не теория

Пользователь — НЕ программист. Это его первая установка OpenClaw.
Его задача: скопировать → выполнить → увидеть → сказать «прошло».
Твоя задача: проводник, не лектор. Одно действие за раз.
```

---

## 🎬 ПРЕЗЕНТАЦИЯ — обновление

`workshop-1/presentation.html` содержит устаревшие данные:
- «12 промптов» → должно быть «11 промптов + 1 ручной onboard» (или просто «11»)
- «1 аудит» → должно быть «3 контура: бот / аудитор / консультант»

Поменять также слайд 8 «Воркшоп 1» — отразить гибридный путь (А1 / А2 / Б).

---

## 🔐 SECURITY — заметки про секреты

В meta-prompt и в Закладке 00 (Подготовка) добавить блок:

> ⚠️ **НИКОГДА не светите API-ключи / Telegram токены в**:
> - публичных чатах
> - видео (записанных или live)
> - git коммитах
> - скриншотах терминала
>
> Если ключ случайно засветился — **сразу ротируй**:
> - MiniMax: platform.minimax.io → Settings → API Keys → Revoke + create new
> - DeepSeek: platform.deepseek.com → API Keys
> - OpenRouter: openrouter.ai → Keys
> - OpenAI: platform.openai.com → API Keys
> - Telegram bot: @BotFather → /mybots → Token → Revoke
>
> После ротации — обнови новые ключи в `.env` и в `~/.openclaw/secrets/` на VPS, перезапусти daemon.

---

## 💡 SSH-КЛИЕНТ — keepalive (важно для длинных сессий)

Добавить в Часть А2 (перед SSH-командой) одноразовый шаг:

```bash
# Один раз на маке — keepalive чтобы SSH не отваливался во время onboard:
mkdir -p ~/.ssh && cat >> ~/.ssh/config <<'EOF'

Host *
  ServerAliveInterval 30
  ServerAliveCountMax 6
EOF
chmod 600 ~/.ssh/config
```

И **сильно рекомендую `tmux`** для устойчивости длинных SSH-сессий:
```bash
# На VPS:
sudo apt install -y tmux
tmux new -s onboard
# Внутри tmux запускать onboard. Если SSH разорвётся:
# - на маке: ssh -i ~/.ssh/clawd_ed25519 clawd@VPS_IP
# - на VPS: tmux attach -t onboard
# Продолжаешь с того же места.
```

---

## 📊 ПОДСЧЁТ ИЗМЕНЕНИЙ

| Файл | Изменения |
|---|---|
| `workshop-1/00-meta-prompt.md` | + блок «СТИЛЬ ОТВЕТОВ», + блок про секреты |
| `workshop-1/01-prompts.md` | расширить Промпт 5 (+ grammy), переписать Промпт 7 (geo-aware), добавить НОВЫЙ Промпт 6.5 |
| `workshop-1/01a-install-by-hand.md` | те же фиксы что в 01-prompts.md |
| `workshop-1/guide.html` | Cheat-sheet (4-5 новых пунктов), Promпты 5/6.5/7, SSH FAQ + tmux + keepalive |
| `workshop-1/presentation.html` | «12 промптов» → «11», слайды под гибрид |
| `standards/workshop-1-standard.md` | C.3 / C.10 переформулировка |
| `knowledge-base/known-issues/` | + 3 новых файла (08, 09, 10) |
| `knowledge-base/CONSULTANT-PROMPT.md` | добавить новые issues в индекс |
| `README.md` (deck) | bump до v1.8.0 |
| Глобальный sed | `openclaw.service` → `openclaw-gateway.service` (везде) |

---

## 🎯 ПРИОРИТЕТЫ ПРИМЕНЕНИЯ

### 🚨 Tier 1 (критичные, без них спринт не работает)
1. `npm i -g grammy` в Промпте 5
2. systemctl unit name (`openclaw-gateway.service`)
3. Cheat-sheet про Hatch your bot (выбирать «Hatch in Terminal»)
4. НОВЫЙ Промпт 6.5 «Tuning после onboard»
5. НОВЫЙ Промпт 7 (geo-aware)
6. Стандарт C.3 пересмотр
7. Геолокационная таблица в Закладке 00

### ⚠️ Tier 2 (важные UX)
8. Cheat-sheet — все остальные новые пункты
9. Pre-flight ping в Промпте 4
10. SSH keepalive + tmux в Часть А2
11. Новые known-issues (08, 09, 10)
12. Meta-prompt стиль ответов

### 💡 Tier 3 (косметика, можно потом)
13. Презентация обновить
14. README с bump-версией
15. CONSULTANT-PROMPT.md обновить индекс

---

## 📜 КАК ПРИМЕНИТЬ

После того как у Дмитрия бот заговорит (любым способом — через DeepSeek primary):

1. Открыть этот файл (`workshop-1/PENDING-FIXES-v1.8.md`)
2. Применить Tier 1 — обязательно
3. Применить Tier 2 — желательно
4. Применить Tier 3 — если есть время
5. Закоммитить как v1.8.0
6. Запушить на GitHub
7. Удалить этот файл (он становится не нужен)
8. Bump README deck → v1.8.0

Ожидаемое время на Tier 1: ~30 минут. На Tier 2: ещё ~30 минут. На Tier 3: ещё ~20 минут.

---

## 🎬 ЛОГ СЕССИИ 2 МАЯ 2026 — что узнали

Реальные сложности при прохождении гайда (4-часовая сессия Дмитрия на VPS Timeweb Москва):

1. **SSH разрывы** во время onboard (idle timeout) — фикс через `ServerAliveInterval` + `tmux`
2. **Папка `Командос` vs `comandos-claw-deck`** — путаница имён. Фикс: Промпт 1 теперь клонирует **в текущую** папку (точка в конце git clone)
3. **`.env` без `ROOT_PASSWORD`** — был баг шаблона. Фикс: добавлен в v1.7.2
4. **`VPS_USER=clawd` по умолчанию** в `.env` — clawd ещё не существует. Фикс: `VPS_USER=root` начально, меняется на clawd после Промпта 4
5. **`ssh ... clawd@VPS_IP`** буквально как команда — не подставляет IP. Фикс: универсальная команда `set -a && source .env && set +a && ssh ...` в v1.7.4
6. **Antigravity Terminal vs Mac Terminal** — оба годятся для onboard. Поправлено в v1.7.4
7. **`grammy` не установлен** — bug в OpenClaw 2026.4.29. Фикс через `npm i -g grammy`
8. **systemctl unit `openclaw-gateway`**, не `openclaw` — фикс везде
9. **dmPolicy=pairing вместо allowlist** — QuickStart режим скипает вопрос. Фикс: 2 команды после onboard (`config set channels.telegram.dmPolicy "allowlist"` + `allowFrom`)
10. **45 bundled deps × 9 плагинов = 18+ сек CPU** на 2-CPU VPS. Фикс: `plugins.allow` whitelist
11. **MiniMax 162ms RTT из Москвы** → fetch-timeout. Фикс: DeepSeek primary для не-Asia VPS
12. **Hatch your bot → Do this later** оставляет scope `operator.pairing`, нет `operator.approvals`. Фикс: всегда «Hatch in Terminal»
13. **AI длинные простыни ответов** для не-тех аудитории — фикс: правило «один шаг за раз» в meta-prompt

---

**Создатель этого файла**: Claude Opus 4.7 (1M context), 2 мая 2026
**Хранилище**: GitHub `Comandosai/sprint-deck-cohort-nov2026` → `workshop-1/PENDING-FIXES-v1.8.md`
**Статус**: накопленный план фиксов, ожидает применения после успешного прохождения сессии
