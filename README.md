# Comandos Claw Deck

> Пульт управления удалённым OpenClaw-агентом на VPS.
> Это рабочее окружение, которое ты открываешь в Antigravity. AI-плагин (Claude Code или Codex) управляет ботом по SSH через скрипты из этой папки.

**Версия deck:** 1.6.0 — knowledge-base (2 МБ ресерча) + AI-консультант + 5-я закладка в гайде
**Подготовлено:** Дмитрий Попов (@ai_comandos)

---

## 🎯 Если ты участник спринта — старт здесь

Открой **`workshop-1/README.md`** — там полный путь Воркшопа 1 от пустого VPS до работающего бота в Telegram.

```
workshop-1/
├── README.md                  ← начни отсюда
├── 00-meta-prompt.md          ← вставляется ОДИН РАЗ в начале В1
├── 01-prompts.md              ← 11 гибридных промптов (AI + ручной onboard)
├── 01a-install-by-hand.md     ← план Б: полностью руками без AI (опционально)
├── 02-self-check.md           ← собрать артефакты от бота
├── 03-audit.md                ← независимый аудит в новом чате
├── guide.html                 ← интерактивный гайд в браузере
└── presentation.html          ← кинематографическая презентация
```

После прохождения Воркшопа 1 → переходи к Воркшопу 2 (через 7 дней).

---

## 📂 Что в этой папке

| Папка | Что там | Когда открывать |
|---|---|---|
| **`workshop-1/`** | Гайд по В1 + промпты + аудит | На Воркшопе 1 |
| **`knowledge-base/`** | 2 МБ ресерча + 7 known-issues + промпт консультанта | Если что-то непонятно или сломалось |
| **`standards/`** | Чек-листы готовности после каждого В | AI и аудитор используют как источник истины |
| **`audit/reports/`** | Отчёты самопроверки и аудита | Создаются участником в процессе В |
| **`workspace/`** | Личность бота (SOUL, USER, AGENTS) | Кастомизация после В1 |
| **`config/`** | Эталонные конфиги: openclaw.json, docker-compose, systemd | Ссылка для AI при настройке |
| **`checklists/`** | Оперативные runbooks: что делать если упало | Когда что-то сломалось |
| **`scripts/`** | Bash для типовых операций (SSH, deploy, healthcheck) | Управление с компа |
| **`docs/`** | Справки: команды бота, troubleshooting, glossary | На лету по ходу работы |
| **`skills/`** | Место для кастомных OpenClaw skills | Воркшоп 3 + post-sprint |

Сам бот живёт **на VPS**, не на твоём компьютере. Эта папка — пульт, не сервер.

---

## 🚀 Первый запуск (быстрый путь)

1. Открой `comandos-claw-deck/` в Antigravity
2. Открой `workshop-1/README.md` и иди по этапам
3. Через 1.5-2 часа у тебя работающий бот в Telegram

Если ты **не участник спринта**, а проходишь сам — те же шаги.

---

## 🎯 Цель Воркшопа 1

После В1 у тебя должно быть:
- ✅ VPS с защитой работает 24/7
- ✅ OpenClaw daemon active
- ✅ Каскад из 4 моделей с MiniMax M2.7 как primary
- ✅ Бот отвечает в Telegram на «привет»
- ✅ Картинки `/image` работают
- ✅ Watchdog защищает от runaway

Полный список критериев: **`standards/workshop-1-standard.md`**

---

## 🔍 Двухконтурная проверка (новое в v1.1)

Главный AI настраивал бота → у него conflict of interest при оценке. 
Поэтому в этом deck два независимых контура проверки:

```
┌─ Контур 1: Главный AI (Antigravity) ──────────┐
│  Прогон 11 промптов в чате с Claude/Codex    │
│  Результат: бот установлен и настроен         │
└────────────────────────────────────────────────┘
                       ↓
┌─ Контур 2: Сам бот в Telegram ────────────────┐
│  8 запросов "пришли свой openclaw.json и т.д." │
│  Бот отдаёт сырые артефакты состояния          │
└────────────────────────────────────────────────┘
                       ↓
┌─ Контур 3: Независимый аудитор (новый чат) ───┐
│  Сравнивает артефакты со standards/            │
│  Выдаёт diff таблицу + вердикт                 │
└────────────────────────────────────────────────┘
```

См. `workshop-1/02-self-check.md` и `workshop-1/03-audit.md`.

---

## 🆘 Что делать если что-то сломалось

| Проблема | Куда смотреть |
|---|---|
| Бот молчит в Telegram | `docs/troubleshooting.md` |
| Деньги утекают (СРОЧНО) | `checklists/emergency-stop.md` |
| VPS умер | `checklists/disaster-recovery.md` |
| Daemon упал | `checklists/gateway-restart.md` |
| Слова непонятны | `docs/glossary.md` |
| MiniMax не работает | Сначала проверь регистр slug: `MiniMax-M2.7` (заглавные!) |

---

## 🛡 Главные правила

- **`.env` НЕ коммитить.** Уже в `.gitignore`.
- **Перед `deploy.sh`** — `git commit`. Откат через `git revert`.
- **Не редактируй конфиги на VPS вручную.** Меняй локально, потом `deploy.sh`.
- **Если что-то горит** — открой `checklists/emergency-stop.md`.

---

## 🏗 Архитектура

```
[Telegram] ←→ [VPS: OpenClaw daemon] ←→ [LLM-провайдеры]
                    ↑
                    │ SSH (через ./scripts/)
                    │
[Этот deck в Antigravity + AI-плагин]
```

Бот в Telegram отвечает с VPS. Ты редактируешь его личность здесь и накатываешь через deploy.

---

## 🔗 Ссылки

- OpenClaw сайт: https://openclaw.ai
- Документация: https://docs.openclaw.ai
- Репозиторий OpenClaw: https://github.com/openclaw/openclaw
- Этот deck на GitHub: https://github.com/Comandosai/sprint-deck-cohort-nov2026

---

## 📝 Что нового в v1.6 (5 мая 2026)

База знаний под рукой + AI-консультант:

- 📚 **`knowledge-base/`** (~2 МБ): 20 блоков ресерча + 5 PRO-материалов + 7 known-issues
- 🆘 **`knowledge-base/CONSULTANT-PROMPT.md`** — готовый промпт для нового чата AI как эксперта
- 🆘 **Закладка 04 «Консультант»** в `workshop-1/guide.html` (фиолетовая) — кнопка копи-паста промпта
- 📋 **7 known-issues** на основе реальной 2-дневной отладки:
  1. `1008-pairing-required` — главная ловушка установки
  2. `path-non-login-shell` — `openclaw: command not found` из cron
  3. `device-pair-disabled` — плагин выключен → нет pairing
  4. `slug-case-sensitive` — `MiniMax-M2.7` vs `minimax-m2.7`
  5. `bot-silent-in-telegram` — универсальный гид «бот молчит»
  6. `runaway-4200-incident` — кейс $4200 за 63 часа
  7. `env-not-in-systemd` — env не пробрасывается в daemon

---

## 📝 Что нового в v1.5 (2 мая 2026)

Этот релиз — результат **двух дней реальной отладки** установки на живой VPS.
Все ловушки задокументированы, промпты переписаны под выверенный путь.

### 🆕 Главные изменения

- 🎯 **Гибридный путь установки**: AI делает рутину (5 промптов), человек делает
  только ручной `openclaw onboard` в Mac Terminal (~10 минут с cheat-sheet),
  AI доделывает тонкости (4 промпта). Итого: ~30 минут вместо ~90.

- 📋 **`workshop-1/01a-install-by-hand.md`** — план Б, полностью ручная
  установка для тех кто не хочет использовать AI на этом этапе.

- 🛡 **Усиленный meta-prompt** с режимами **DIAGNOSE → FIX → VERIFY** и
  явным запретом на запуск `openclaw onboard` через AI (ловушка №1).

### 🐛 Исправленные ловушки OpenClaw 2026.4.x

- **1008 pairing required** — onboard через `--non-interactive --auth=skip`
  оставляет CLI в read-only scope. Любой запрос к моделям → 1008.
  Фикс: ручной onboard с `auth=token` + `device-pair` плагин включён.

- **PATH в non-login shell** — npm prefix виден только в interactive bash.
  Cron, systemd, ssh-batch не видят. Фикс: PATH в три файла
  (`~/.bashrc`, `~/.profile`, `~/.bash_profile`) + использование `bash -lc`.

- **Slug case-sensitive** — `minimax/MiniMax-M2.7` (с заглавными), не
  `minimax/minimax-m2.7`. Иначе probe падает, fallback на DeepSeek.

- **Plugin device-pair выключен** — встречалось когда конфиг лепили руками
  без `onboard`. Без этого плагина любой scope-upgrade → 1008.

### 📜 Из v1.0-v1.4

- ✅ `workshop-1/` — папка с полным гайдом В1
- ✅ `standards/workshop-1-standard.md` — ~30 критериев готовности
- ✅ `audit/` — фреймворк независимого аудита
- ✅ Self-check через сам Telegram-бот (8 запросов)
- ✅ Независимый аудитор в новом чате
- ✅ `workshop-1/guide.html` — интерактивный HTML-гайд (брендинг COMANDOS AI)
- ✅ `workshop-1/presentation.html` — кинематографическая презентация спринта
