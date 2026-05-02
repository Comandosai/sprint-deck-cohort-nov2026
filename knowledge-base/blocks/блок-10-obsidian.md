# Блок 10: Obsidian-интеграция

> **Что:** Связка OpenClaw memory с Obsidian-vault через симлинк, чтобы агент работал в твоей базе знаний, а ты видел его память глазами в любимом редакторе.
> **Зачем:** Перестать читать `MEMORY.md` через `cat`, подключить backlinks, графы, теги и плагины Obsidian; синхронизировать память на iPhone; делать ручные правки в живой базе.
> **Время:** 30–45 минут (фактически: 45–75 минут с устранением конфликтов с iCloud/Sync).

---

## ⚠️ ВАЖНЫЙ ДИСКЛЕЙМЕР (читать первым)

В индексе официальной документации **`docs.openclaw.ai/llms.txt` ОТСУТСТВУЕТ** страница про Obsidian-интеграцию. Это значит:

1. **В OpenClaw НЕТ встроенной Obsidian-интеграции** — нет `claw plugin install obsidian`, нет официального скилла `obsidian-sync`.
2. Подход через симлинк `~/.openclaw/workspace/memory` ↔ Obsidian vault — это **community-практика**, не официальная фича.
3. Скиллы из ТЗ Дмитрия (`qmd-external`, `obsidian-sync`) — гипотетические или community-уровня. Их статус нужно проверить на ClawHub: **[VERIFY на hub.openclaw.ai]**.
4. Memory-система OpenClaw реальна — она хранит файлы в `~/.openclaw/workspace/memory/` (`MEMORY.md`, daily logs, тематические файлы). Именно эту директорию мы и подменяем симлинком.
5. Term **"QMD cross-indexing"** из исходного описания **не подтверждён** ни в индексе OpenClaw, ни в Obsidian-экосистеме. Возможные интерпретации: (a) Quartz Markdown (статика-генератор); (b) аббревиатура клиента — нужно уточнить у Дмитрия. **[VERIFY]** Замена для практики: Obsidian Dataview + Smart Connections.

Поскольку всё это **community-уровень**, блок построен на проверенных Obsidian best practices, а не на «как сказано в доке OpenClaw».

---

## 🎯 Цель блока

После выполнения у тебя должно быть:

- [x] Установлен Obsidian desktop (и опционально мобильный) — vault создан в стабильном месте.
- [x] `~/.openclaw/workspace/memory/` — это симлинк на `~/Obsidian/MyVault/AgentMemory/`.
- [x] OpenClaw читает/пишет в эту папку как раньше; Obsidian показывает те же файлы как заметки с backlinks, тегами и frontmatter.
- [x] Phase 0 (read-only): агент пока **только читает** vault, не пишет. Конфиг `fs.allow` сужен.
- [x] Установлен `obsidian-cli` (community-проект Yakitrak) — для скриптовых действий.
- [x] Структурированный шаблон vault: `AgentMemory/`, `daily/`, `topics/`, `.private/`, `.ignored/`.
- [x] Frontmatter-схема для тематических заметок (Dataview-friendly).
- [x] Тест: создаёшь заметку «test-marker.md» в Obsidian → агент в Telegram её находит через `/recall`.

---

## ⚡ Что нового в апреле 2026

> Дисклеймер: это компиляция реальных трендов Obsidian + community-практик. Конкретные версии плагинов меняются — фиксируй то, что у тебя работает.

- **Obsidian 1.7+** (актуальная ветка к апрелю 2026): нативный Bases (структурированные view как в Notion), улучшенный Properties UI, Web Clipper стабилен.
- **Smart Connections** (community-плагин Brian Petro): локальные эмбеддинги (Ollama / transformers.js) — даёт агенту semantic search по vault без отправки наружу. Альтернатива покупной Mem0 для простых кейсов.
- **Copilot for Obsidian** (Logan Yang): локальные/cloud LLM прямо в Obsidian; полезен **тебе**, не агенту, но они смотрят в один vault.
- **Dataview 0.5.x → DataviewJS** + **Bases**: запросы по frontmatter превращаются в живые таблицы — агент пишет факты с тегами, ты видишь дашборды.
- **Obsidian Sync 2026**: end-to-end шифрование, $10/мес, mobile incl. Альтернативы — Syncthing (бесплатно, чуть сложнее), iCloud (плохо для конкурентного доступа агента и iPhone), Git (отлично для версионирования, плохо для real-time mobile).
- **obsidian-cli (Yakitrak)**: github.com/Yakitrak/obsidian-cli — CLI для daily note, search, open. Реальный, активный проект.
- **OpenClaw memory секция** в `~/.openclaw/openclaw.json` уже даёт `search/compaction/contextPruning/dailyLogs` — мы лишь меняем физический путь хранения через симлинк, конфиг не ломаем.
- **Bases (Obsidian 1.7+)**: бета-фича, превращает folder + frontmatter в таблицу. Можно делать «база фактов агента» с фильтрами по `entity`, `confidence`, `last_seen`.

---

## 🛠️ Конкретные инструменты и версии

| Инструмент | Версия (апр 2026) | Зачем | Где взять |
|---|---|---|---|
| Obsidian Desktop | 1.7.x | Основной редактор vault | obsidian.md/download |
| Obsidian Mobile (iOS/Android) | 1.7.x | Доступ к памяти агента с телефона | App Store / Play |
| obsidian-cli (Yakitrak) | 0.5+ | Скрипты, открыть/найти из терминала | `npm i -g obsidian-cli` (см. репо) |
| Smart Connections | 2.x | Локальные эмбеддинги, semantic search | Community Plugins в Obsidian |
| Dataview | 0.5.x | Запросы по frontmatter | Community Plugins |
| Templater | 2.x | Шаблоны для daily/topic notes | Community Plugins |
| Periodic Notes | 1.x | Daily/weekly notes по расписанию | Community Plugins |
| Syncthing | 1.27+ | Бесплатная синхронизация vault на VPS / mobile | syncthing.net |
| `ln` (Linux/macOS) | builtin | Симлинк | — |
| `mklink /J` (Windows) | builtin | Junction | cmd /admin |
| OpenClaw | latest | Хост агента | docs.openclaw.ai |

---

## 💡 Лайфхаки и про-приёмы (12 штук)

### 1. Симлинк направление: vault — источник, memory — псевдоним

Делай **симлинк со стороны OpenClaw на vault**, а не наоборот. Тогда:
- Vault — твой контролируемый объект (бэкапится, версионируется Git).
- `~/.openclaw/workspace/memory/` — техническая ссылка, удалить и пересоздать ничего не сломает.
- Если переустановишь OpenClaw — данные останутся, просто пересоздашь линк.

```bash
# СНАЧАЛА забэкапь существующую memory:
mv ~/.openclaw/workspace/memory ~/.openclaw/workspace/memory.backup-$(date +%F)
mkdir -p ~/Obsidian/MyVault/AgentMemory
# Перенеси старые файлы в vault:
cp -R ~/.openclaw/workspace/memory.backup-*/. ~/Obsidian/MyVault/AgentMemory/
# Создай симлинк:
ln -s ~/Obsidian/MyVault/AgentMemory ~/.openclaw/workspace/memory
```

### 2. Phase 0: read-only — сужай `fs.allow`, а не надейся на дисциплину

В первую неделю агент должен **только читать** vault. Это спасёт от случайного перезаписывания твоих заметок при кривом промпте. В `~/.openclaw/openclaw.json`:

```json5
{
  "memory": {
    "path": "~/.openclaw/workspace/memory", // симлинк
    "writeMode": "read-only", // [VERIFY: точное имя поля в твоей версии]
    "search": { "enabled": true },
    "dailyLogs": { "enabled": true, "writePath": "~/.openclaw/workspace/memory.write-buffer" }
  },
  "fs": {
    "allow": [
      { "path": "~/Obsidian/MyVault/AgentMemory", "mode": "r" },
      { "path": "~/.openclaw/workspace/memory.write-buffer", "mode": "rw" }
    ],
    "deny": [
      { "path": "~/Obsidian/MyVault/.private" },
      { "path": "~/Obsidian/MyVault/AgentMemory/.ignored" }
    ]
  }
}
```

Идея: агент пишет в **отдельный буфер**, ты раз в день вручную мёрджишь нужное в vault. Через неделю откроешь write на `AgentMemory/` целиком.

### 3. Privacy: `.private/` и `.ignored/` папки

В корне vault создай `.private/` (твои дневники, личные заметки) и в `AgentMemory/.ignored/` (черновики, которые агент не должен видеть). **Имя с точкой** — Obsidian их показывает (если не в `.obsidian/`), но `fs.deny` их прячет от агента.

```bash
mkdir -p ~/Obsidian/MyVault/.private
mkdir -p ~/Obsidian/MyVault/AgentMemory/.ignored
echo "# Личное — агент не видит" > ~/Obsidian/MyVault/.private/dnevnik.md
```

Бонус: добавь `.private/` в `.obsidianignore` (если плагин Files есть) — Smart Connections тоже не индексирует.

### 4. Frontmatter-схема для агентских фактов

Чтобы агент мог писать структурированно (а Dataview/Bases — читать), договорись о схеме. Создай `AgentMemory/_TEMPLATE.md`:

```yaml
---
type: fact          # fact | task | decision | idea | observation
entity: "Дмитрий"   # о ком/чём
topic: "marketing"  # или массив
confidence: 0.8     # 0..1
source: "telegram-2026-04-29-msg-142"
created: 2026-04-29
last_seen: 2026-04-29
tags: [agent, fact]
---
Тело заметки в свободной форме. Можно [[ссылки]] на другие сущности.
```

В системном промпте агента (Блок 5) добавь: «Когда создаёшь заметку памяти, используй фронтматтер из `_TEMPLATE.md`».

### 5. Dataview-дашборд: что агент знает обо мне

Создай заметку `AgentMemory/_INDEX.md` — твой контрольный экран. Агент туда **не пишет**, ты только читаешь:

````markdown
# Что агент помнит

## Свежие факты (последние 7 дней)
```dataview
TABLE entity, topic, confidence, last_seen
FROM "AgentMemory"
WHERE type = "fact" AND last_seen >= date(today) - dur(7 days)
SORT last_seen DESC
LIMIT 50
```

## Задачи в работе
```dataview
LIST FROM "AgentMemory" WHERE type = "task" AND !completed
```

## Решения за месяц
```dataview
TABLE topic, file.ctime
FROM "AgentMemory" WHERE type = "decision"
SORT file.ctime DESC LIMIT 20
```
````

Это ОЧЕНЬ круто: видишь живую память агента табличкой.

### 6. Daily logs: путь как у Obsidian Daily Note

OpenClaw `dailyLogs` пишет в свою структуру; настрой формат под Obsidian Periodic Notes — будет один файл, два приложения видят как родной.

```json5
"dailyLogs": {
  "enabled": true,
  "format": "YYYY-MM-DD",        // соответствует Obsidian Periodic Notes по умолчанию
  "folder": "daily",             // ~/...AgentMemory/daily/2026-04-29.md
  "template": "daily-template.md"
}
```

В Obsidian → Settings → Periodic Notes → Daily Notes → Folder = `AgentMemory/daily`. Теперь `Ctrl+Shift+D` открывает файл, в который агент пишет sumарии.

### 7. Backlinks как «контекст по умолчанию»

Заведи правило в системном промпте агента: «При написании факта о сущности всегда ставь `[[wikilink]]` на основную страницу этой сущности (`AgentMemory/entities/Дмитрий.md`, `entities/OpenClaw.md`, etc.)».

Эффект: в Obsidian → откроешь `Дмитрий.md` → во вкладке Backlinks увидишь ВСЁ, что агент про тебя записал. Это удобнее, чем грепать `MEMORY.md`.

### 8. obsidian-cli — мост между shell и vault

```bash
# Установка (Yakitrak/obsidian-cli)
npm install -g obsidian-cli
# Открыть заметку
obs open "AgentMemory/_INDEX.md" --vault MyVault
# Создать daily note
obs daily --vault MyVault
# Поиск (через Obsidian search API)
obs search "OpenClaw" --vault MyVault
```

Скилл-обёртка для агента: создай в OpenClaw skill `obsidian-cli-wrapper`, который вызывает `obs search` и парсит результат — даст агенту нормальный full-text поиск через тот же индексер, который видит человек.

> [VERIFY]: точные команды зависят от версии obsidian-cli; проверь `obs --help`.

### 9. Mobile (iPhone): Obsidian Sync vs Syncthing

| Сценарий | Что выбрать |
|---|---|
| Готов платить $10/мес, нужен e2e | **Obsidian Sync** — официальный, надёжный, mobile поддерживает. |
| VPS Linux + Mac + iPhone, бесплатно | **Syncthing** на VPS и Mac, на iPhone — Möbius Sync ($5 одноразово) или Mobius Sync. |
| Нужно версионирование, не нужен real-time | **Git** + Working Copy на iPhone. |
| iCloud | **НЕ РЕКОМЕНДУЮ** — конфликты с агентом, который пишет на VPS. |

Главное правило: **vault либо в iCloud, либо у агента — не оба сразу**, иначе будут `.conflict-*.md` файлы.

### 10. Конфликты Sync: ставь `.gitattributes` + lock-файлы наружу

Если используешь Obsidian Sync **и** Git одновременно (бывает у задротов): добавь в `.gitignore` корня vault: `.obsidian/workspace*`, `.obsidian/cache`, `.trash/`, `.smart-connections/`. Иначе каждое открытие vault на другом устройстве == git conflict.

```gitignore
# ~/Obsidian/MyVault/.gitignore
.obsidian/workspace*
.obsidian/cache
.obsidian/plugins/*/data.json
.trash/
.smart-connections/
*.conflict-*.md
.DS_Store
```

### 11. Атомарная запись, чтобы агент не словил половинку файла

Если агент часто пишет в memory, а Obsidian Sync параллельно читает — бывает чтение полу-записанного файла. Решение: **писать через `tmpfile + rename`**, а не open-write-close. В скилле памяти OpenClaw (если кастомный):

```python
import os, tempfile, shutil
def atomic_write(path, content):
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        f.write(content)
    os.replace(tmp, path)  # атомарный rename
```

`os.replace` атомарен на одной ФС — Obsidian увидит либо старую, либо новую версию, без половинок.

### 12. Backup стратегия: Git + еженедельный rsync на VPS

Vault — твоя интеллектуальная собственность. Бэкапь его два уровня:

```bash
# 1. Git ежедневно (cron на ноуте)
0 22 * * * cd ~/Obsidian/MyVault && git add -A && git commit -m "auto $(date +\%F)" && git push

# 2. Rsync еженедельно на VPS
0 3 * * 0 rsync -av --delete ~/Obsidian/MyVault/ user@vps:/backups/obsidian-vault/
```

Privacy: репозиторий **приватный**, `.private/` в `.gitignore`.

---

## 📋 Готовые команды и конфиги

### Установка Obsidian (macOS / Linux)

```bash
# macOS
brew install --cask obsidian

# Linux (AppImage)
wget https://github.com/obsidianmd/obsidian-releases/releases/latest/download/Obsidian-1.7.X.AppImage
chmod +x Obsidian-*.AppImage
mv Obsidian-*.AppImage ~/Applications/

# Создание vault структуры
mkdir -p ~/Obsidian/MyVault/{AgentMemory/{daily,topics,entities,.ignored},.private}
cd ~/Obsidian/MyVault
git init && echo ".obsidian/workspace*" > .gitignore
```

### Симлинк (macOS / Linux)

```bash
# Phase 0: бэкап + симлинк
mv ~/.openclaw/workspace/memory ~/.openclaw/workspace/memory.backup-$(date +%F)
cp -R ~/.openclaw/workspace/memory.backup-*/. ~/Obsidian/MyVault/AgentMemory/ 2>/dev/null
ln -s ~/Obsidian/MyVault/AgentMemory ~/.openclaw/workspace/memory

# Проверка
ls -la ~/.openclaw/workspace/memory
# должно показать: memory -> /Users/.../Obsidian/MyVault/AgentMemory
readlink ~/.openclaw/workspace/memory
```

### Симлинк (Linux VPS)

```bash
# На VPS — vault может жить прямо в /home/claw/Obsidian (без GUI Obsidian)
mkdir -p /home/claw/Obsidian/AgentVault/AgentMemory
ln -s /home/claw/Obsidian/AgentVault/AgentMemory /home/claw/.openclaw/workspace/memory

# Sync с локальной машиной через Syncthing — vault `AgentVault` шарится
```

### Junction (Windows)

```cmd
:: От администратора
mkdir "%USERPROFILE%\Obsidian\MyVault\AgentMemory"
mklink /J "%USERPROFILE%\.openclaw\workspace\memory" "%USERPROFILE%\Obsidian\MyVault\AgentMemory"
```

> Symlink (`mklink /D`) требует Developer Mode или admin; **junction (`/J`) работает у обычного юзера** и для большинства задач достаточно.

### `~/.openclaw/openclaw.json` — фрагмент memory (Phase 0, read-only)

```json5
{
  "memory": {
    "path": "~/.openclaw/workspace/memory",
    "search": {
      "enabled": true,
      "indexer": "ripgrep",            // [VERIFY: точное имя в твоей версии]
      "include": ["**/*.md"],
      "exclude": [".obsidian/**", ".trash/**", ".ignored/**", ".private/**"]
    },
    "compaction": {
      "enabled": true,
      "trigger": "size:100k|days:30"
    },
    "contextPruning": {
      "enabled": true,
      "keep": ["entities/**", "_INDEX.md"]
    },
    "dailyLogs": {
      "enabled": true,
      "folder": "daily",
      "format": "YYYY-MM-DD",
      "template": "_TEMPLATES/daily.md"
    }
  },
  "fs": {
    "allow": [
      { "path": "~/Obsidian/MyVault/AgentMemory", "mode": "r" },
      { "path": "~/.openclaw/workspace/memory-write-buffer", "mode": "rw" }
    ],
    "deny": [
      { "path": "~/Obsidian/MyVault/.private" },
      { "path": "~/Obsidian/MyVault/AgentMemory/.ignored" },
      { "path": "**/.obsidian/**" }
    ]
  }
}
```

> **[VERIFY]** имена полей `writeMode`, `indexer`, `mode: "r"` — это разумные предположения по конфигу OpenClaw, точное API смотри в `docs.openclaw.ai/configuration` после публикации блока. Если не совпадает — структура остаётся та же, переименуешь ключи.

### Шаблон daily-note (Templater-friendly)

Положи в `~/Obsidian/MyVault/AgentMemory/_TEMPLATES/daily.md`:

```markdown
---
type: daily
date: <% tp.date.now("YYYY-MM-DD") %>
tags: [daily, agent]
---

# <% tp.date.now("YYYY-MM-DD, dddd") %>

## События дня
-

## Что агент сделал
-

## Что я сказал агенту (важное)
-

## Завтра
-
```

### obsidian-cli быстрые команды

```bash
# Установка
npm install -g obsidian-cli

# Открыть _INDEX
obs open "AgentMemory/_INDEX" --vault MyVault

# Создать новую заметку из терминала
obs new "AgentMemory/topics/openclaw-setup" --vault MyVault

# Посмотреть список vault'ов
obs vault list
```

### Тест Phase 0 (read-only)

```bash
# 1. Создаёшь заметку в Obsidian руками:
echo "---
type: fact
entity: test
tags: [test-marker]
---
Тестовая заметка для агента: marker-29-04-2026-XYZ" \
> ~/Obsidian/MyVault/AgentMemory/topics/test-marker.md

# 2. В Telegram пишешь агенту:
# "Найди в памяти заметку с маркером marker-29-04-2026-XYZ"

# 3. Если агент возвращает её содержание — read работает.

# 4. Просишь агента: "Удали эту заметку".
# В Phase 0 агент должен ответить «нет прав» — fs.deny / read-only сработал.
```

---

## ⚠️ Подводные камни

1. **iCloud + симлинк = боль.** macOS перемещает Obsidian vault в iCloud Drive автоматически, если положил в `~/Documents/`. Симлинк `~/.openclaw/workspace/memory` начинает указывать на cloud-stub файл (`.icloud`). Решение: vault строго в `~/Obsidian/`, **никогда** в `~/Documents/`.

2. **Obsidian Sync vs два пишущих клиента.** Если агент на VPS пишет в vault, а ты на Mac правишь те же файлы — Sync создаёт `*.conflict-*.md`. Phase 0 read-only от этого защищает; в Phase 1 (write) пиши в `daily/` и `topics/agent/` — туда сам не лазь.

3. **`.obsidian/workspace.json` mutates each open.** Обсидиан пишет UI-state в этот файл при каждом запуске → создаёт спам в Git. Всегда добавляй его в `.gitignore`.

4. **Symlink через Obsidian Sync не передаётся.** Sync синкает **содержимое vault**, симлинк живёт в `~/.openclaw/workspace/memory` (вне vault) — он на каждой машине свой. Это нормально, но если вообще удалишь симлинк — потеряешь связь.

5. **Smart Connections индексирует .private, если не настроишь.** Открой плагин → Settings → Excluded folders → добавь `.private`, `.ignored`, `.trash`. Иначе твой дневник попадёт в эмбеддинги.

6. **Daily Notes конфликт.** Если у тебя уже была daily-структура в Obsidian (`Daily/2026-04-29.md`) и OpenClaw тоже хочет писать `daily/` — пути разойдутся. Договорись об **одной** папке `AgentMemory/daily/` для обоих.

7. **Wikilinks `[[name]]` против relative `[name](./file.md)`.** OpenClaw memory обычно пишет relative-ссылки; Obsidian рендерит и те, и те, но backlinks работают только с wikilinks. Скажи агенту в системном промпте: «используй `[[wikilinks]]` без расширения».

8. **Большие vault → медленная индексация.** Если vault > 10k заметок, Smart Connections ест RAM. Для агентского AgentMemory это редко проблема, но если хранишь там transcripts на гигабайт — выноси их в `topics/transcripts/.no-index/` и исключи.

9. **Frontmatter-парсер OpenClaw vs Obsidian.** Obsidian принимает любой YAML; OpenClaw memory может фейлиться на массивах в одну строку (`tags: [a, b]` vs `tags:\n  - a\n  - b`). Используй блочный YAML (с `\n  - `) — оба парсера ок.

10. **Permissions при create symlink на macOS под другим user.** Если OpenClaw запущен под `claw`, а Obsidian — под `dmitriy`, симлинк должен принадлежать `claw` и указывать на путь, доступный `claw`. Решение: vault в общедоступной папке (`/Users/Shared/Obsidian/`), либо запускай агента под своим user.

11. **`.openclaw/workspace/memory` уже существует как папка.** Команда `ln -s` фейлится — нужно `mv` сначала. Никогда **не** делай `rm -rf` не глядя — там может быть месяц истории агента.

12. **Mobile + Syncthing задержка ~10–60 сек.** Если в дороге пишешь в Obsidian Mobile и сразу спрашиваешь агента — он может не увидеть. Дай sync дойти до сервера, либо используй Obsidian Sync (быстрее).

---

## ✅ Чек-лист выполнения

### Подготовка (5 мин)
- [ ] Obsidian установлен на основной машине.
- [ ] Vault создан в `~/Obsidian/MyVault/` (не в iCloud!).
- [ ] Структура папок: `AgentMemory/`, `AgentMemory/daily/`, `AgentMemory/topics/`, `AgentMemory/entities/`, `AgentMemory/.ignored/`, `.private/`.
- [ ] `.gitignore` настроен (`.obsidian/workspace*`, `.private/` etc.).

### Симлинк (5 мин)
- [ ] Существующая `~/.openclaw/workspace/memory` забэкаплена.
- [ ] Контент перенесён в `AgentMemory/`.
- [ ] Симлинк создан и проверен через `readlink`.
- [ ] OpenClaw перезапущен; команда `/recall` в Telegram отвечает (доказательство — путь жив).

### Phase 0: read-only (10 мин)
- [ ] `openclaw.json` сужен: `fs.allow` на vault — только `r`.
- [ ] `fs.deny` на `.private`, `.ignored`, `.obsidian`.
- [ ] Тест-маркер создан в Obsidian, агент находит.
- [ ] Агент при попытке записи отвечает «нет прав».

### Obsidian-плагины (10 мин)
- [ ] Templater + шаблоны daily/topic.
- [ ] Periodic Notes → Daily Notes folder = `AgentMemory/daily`.
- [ ] Dataview включён.
- [ ] `_INDEX.md` создан с дашбордом.
- [ ] Smart Connections (опционально, если хочешь semantic search в Obsidian) с excluded `.private/.ignored`.

### Tooling (5 мин)
- [ ] `obsidian-cli` установлен, `obs open` работает.
- [ ] `obs search "test-marker"` находит созданную заметку.

### Backup (5 мин)
- [ ] `git init` в vault, первый коммит.
- [ ] Cron на ноуте: ежедневный auto-commit.
- [ ] Rsync на VPS настроен (опционально).

### Mobile (опционально, 10–15 мин)
- [ ] Obsidian Mobile установлен.
- [ ] Sync настроен (Obsidian Sync **или** Syncthing **или** Git+Working Copy — выбери одно).
- [ ] На iPhone открывается тот же vault, видит заметки агента.

---

## 🧪 Верификация

**Стресс-тест 1: Read из Obsidian → агент видит**
1. В Obsidian создаёшь `AgentMemory/topics/sushi-2026.md` с фронтматтером и текстом «Я обожаю спайси-тунец из Yakuza, не люблю авокадо».
2. Через 30 секунд (sync если есть) пишешь агенту: «Что ты знаешь о моих суши-предпочтениях?»
3. **Ожидание:** агент отвечает с упоминанием спайси-тунца и авокадо. Если нет — проверь search.exclude и индексатор.

**Стресс-тест 2: Phase 0 — write забанен**
1. Просишь агента: «Запиши в память: моя любимая книга — Дюна».
2. **Ожидание:** агент либо пишет в `memory-write-buffer/` (если включил), либо честно говорит «не имею прав на запись в vault».
3. Проверка: `grep -ri "Дюна" ~/Obsidian/MyVault/AgentMemory/` — не должно быть найдено.

**Стресс-тест 3: Backlinks работают**
1. Создай `AgentMemory/entities/Дмитрий.md` с фронтматтером.
2. Попроси агента (когда включишь write в Phase 1): «Запиши факт обо мне с wikilink».
3. В Obsidian открой `entities/Дмитрий.md` → Backlinks pane → должна появиться ссылка из новой заметки.

**Стресс-тест 4: Privacy — `.private` не видна агенту**
1. Создай `~/Obsidian/MyVault/.private/секрет.md` с уникальным маркером.
2. Спроси агента про этот маркер.
3. **Ожидание:** агент не находит. Если находит — `fs.deny` не работает, проверь конфиг.

**Стресс-тест 5: Mobile sync**
1. На iPhone в Obsidian Mobile создай заметку `AgentMemory/topics/from-mobile.md`.
2. Подожди 1–2 минуты.
3. Спроси агента: «Найди from-mobile в памяти». Должен найти.

---

## ⏱ Реальная оценка времени

| Этап | План | Реально |
|---|---|---|
| Установка Obsidian + vault | 5 мин | 5–10 мин |
| Симлинк + бэкап старой памяти | 5 мин | 10 мин (с проверками) |
| Конфиг `openclaw.json` Phase 0 | 10 мин | 15–20 мин (поиск точных имён полей) |
| Плагины Obsidian + шаблоны | 10 мин | 15–25 мин (Templater настраивается с матом) |
| obsidian-cli | 5 мин | 5–10 мин |
| Тесты | 5 мин | 10–15 мин |
| Mobile (если делаешь) | +15 мин | +30 мин (Syncthing) или +10 (Obsidian Sync) |
| **Итого** | **30–45 мин** | **45–75 мин**, mobile отдельно |

---

## 🔗 Связи с другими блоками

**ДО (зависимости):**
- **Блок 6 — Память настроена.** Нельзя делать симлинк, пока не понимаешь, что и куда пишет OpenClaw memory. Сначала запусти `MEMORY.md`, daily logs, убедись что компакция работает — потом подменяй путь.
- Блок 5 (Личность): системный промпт должен включать инструкции про frontmatter и `[[wikilinks]]`.
- Блок 11 (Безопасность): `fs.allow/deny`, права `claw`-юзера.

**ПОСЛЕ (что разблокируется):**
- **Блок 15 — Mem0 / Векторная память.** Vault становится источником эмбеддингов; Smart Connections + Mem0 на одной базе.
- **Блок 20 — Режим бога / Автоматизация.** Когда агент пишет в Obsidian с тегами, Dataview даёт тебе живые дашборды без отдельной БД.
- Блок 12 (Проактивность): агент может слать уведомления типа «Я обновил `entities/Дмитрий.md`, посмотри backlinks».
- Блок 18 (Мобильные ноды): через Obsidian Mobile + Sync память агента доступна с iPhone и в любой точке без bot-интерфейса.

---

## 📚 Источники

**Подтверждённые:**
- Obsidian official docs — `help.obsidian.md` (versioning, Properties, Bases beta).
- `github.com/Yakitrak/obsidian-cli` — реальный community CLI (проверь актуальную версию).
- `github.com/brianpetro/obsidian-smart-connections` — Smart Connections plugin.
- `github.com/blacksmithgu/obsidian-dataview` — Dataview.
- Obsidian Sync pricing — `obsidian.md/sync`.
- Syncthing docs — `docs.syncthing.net` (для Linux/VPS).

**С пометкой [VERIFY]:**
- `docs.openclaw.ai/configuration` — точные имена полей `memory.writeMode`, `memory.search.indexer`, `fs.allow.mode`. Возможно отличается от моего предположения; структура та же.
- `hub.openclaw.ai` — наличие community-скиллов `qmd-external`, `obsidian-sync`. Если есть — можно сократить часть лайфхаков и опереться на готовое.
- Term **«QMD cross-indexing»** из исходного описания — не подтверждён ни в OpenClaw, ни в Obsidian. Уточнить у Дмитрия. Текущая замена: Obsidian Dataview + Smart Connections.

**НЕТ официальной интеграции OpenClaw ↔ Obsidian** в индексе `docs.openclaw.ai/llms.txt` — весь блок построен как community-практика поверх реальной memory-системы OpenClaw.

---

> **TL;DR:** Obsidian становится твоим окном в память агента через симлинк `~/.openclaw/workspace/memory → ~/Obsidian/MyVault/AgentMemory`. Phase 0 строго read-only через `fs.allow`. Шаблон vault: `daily/`, `topics/`, `entities/`, `.private/`, `.ignored/`. Frontmatter + Dataview = живые дашборды. Backup — Git ежедневно. Mobile — Obsidian Sync или Syncthing. Никакой iCloud в vault.
