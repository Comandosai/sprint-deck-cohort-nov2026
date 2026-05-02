# Блок 14: Git workflow

> **Что:** настройка Git-страховки для конфигурации OpenClaw в `~/.openclaw/workspace` с автокоммитами, шифрованием секретов и приватным remote-репозиторием.
> **Зачем:** не потерять часы работы агента (память, скиллы, конфиги) при сбое VPS, ошибочном `rm -rf` или внезапном «галлюцинировании» агента, который сам себе перезаписал `MEMORY.md`.
> **Время:** реалистично — 45–60 минут (не 30, как в исходном описании): `git init` + `.gitignore` + GitHub-репо + git-crypt + cron + первый push + тест восстановления.

---

## Цель блока

Создать «бронежилет» для всей пользовательской конфигурации OpenClaw:

1. **Версионирование.** Каждое изменение `MEMORY.md`, `SOUL.md`, `AGENTS.md`, `USER.md`, `HEARTBEAT.md` отслеживается в Git. Можно откатиться на любую точку.
2. **Off-site backup.** Приватный репозиторий на GitHub (или Codeberg/Forgejo) — если VPS, MacBook или диск умрут, конфиг восстанавливается за 5 минут.
3. **Безопасность секретов.** `openclaw.json` с реальными токенами (TELEGRAM_BOT_TOKEN, OPENAI_API_KEY, ANTHROPIC_API_KEY, e-mail, ssh-keys) **никогда** не попадает в репо в открытом виде. Используется `git-crypt` или `sops + age`.
4. **Автоматизация.** Cron каждый час делает `git add . && git commit -m "auto: $(date)"` и `git push` — без участия Дмитрия.
5. **Защита от случайностей.** `pre-commit` хук с `gitleaks` блокирует коммит, если в diff проскочил токен.
6. **Восстановление.** Документированный runbook: «VPS сгорел → ssh новый → git clone → `npm i -g openclaw` → 1 команда → агент жив».

Это страховка для **всех** остальных блоков спринта — без неё любая ошибка означает потерю прогресса.

---

## Что нового в апреле 2026

- **gitleaks 8.27** (релиз февраль 2026) — добавлен детектор для Anthropic API keys (`sk-ant-...`) и OpenClaw config tokens (`oc_live_...`). Раньше приходилось писать кастомные правила.
- **git-crypt 0.8.0** — наконец-то официально поддерживает Apple Silicon (homebrew bottle, без сборки из исходников). До 2025 на M1/M2/M3 надо было компилировать вручную.
- **sops 3.10.x** + **age 1.2.x** — стали стандартом де-факто вместо PGP. Пара ключей умещается в один файл, не требует gpg-agent. На Reddit r/selfhosted в феврале 2026 — горячее обсуждение, многие мигрировали с git-crypt на sops+age именно из-за простоты.
- **GitHub** в марте 2026 включил по умолчанию **Push Protection** для приватных репо бесплатных тарифов (раньше — только Enterprise). Если в push есть секрет — GitHub блокирует на стороне сервера, даже если pre-commit хук сломан.
- **OpenClaw 1.4** (релиз 2026-03-15) — в `openclaw init` появился флаг `--git`, который делает `git init`, генерирует базовый `.gitignore` и `openclaw.json.example` сам. Если ставите свежий OpenClaw — половину блока он сделает автоматически.
- **Codeberg** в январе 2026 ввёл лимит 100 репо/аккаунт бесплатно (до этого было безлимитно) — но для одного конфига более чем хватает.
- **Forgejo 9.0** (Q1 2026) — стал self-hostable альтернативой №1 после форка из Gitea, имеет нативный SSH-actions runner, что удобно для автокоммита изнутри VPS.
- **GitHub Actions** ввёл новый `secret-scanning-v3` action — можно повесить на pre-push hook и проверить весь репо локально командой `gh secret-scan local`.

---

## Конкретные инструменты и версии

| Инструмент | Версия | Зачем | Альтернатива | Выбор и почему |
|---|---|---|---|---|
| **git** | 2.45+ | Базовый VCS | Mercurial, Fossil | Git — стандарт, integrations с GitHub. На macOS ставится через Xcode CLT или `brew install git`. |
| **gitleaks** | 8.27 | Сканер секретов в pre-commit | trufflehog, talisman | Быстрее trufflehog (Go vs Python), правила обновляются ежемесячно, есть baseline-mode для legacy-репо. |
| **git-crypt** | 0.8.0 | Прозрачное шифрование файлов в Git | sops+age, BlackBox | Прозрачно для пользователя: после `git-crypt unlock` файлы выглядят как plain. Для конфигов агента — идеально. |
| **sops** | 3.10.2 | Шифрование на уровне values в YAML/JSON | git-crypt, vault | Лучше для granular-шифрования (только поля `*.token`, остальной JSON открыт и читаем в diff). |
| **age** | 1.2.1 | Современный crypto для sops | GPG | Простой ключ-файл, не требует agent, работает out-of-the-box на macOS. |
| **GitHub** (Free) | — | Hosting приватного репо | Codeberg, GitLab, Forgejo | Бесплатные приватные репо, push protection, SSO, привычный UI. Для бэкапа агента — overkill, но удобно. |
| **GitHub CLI** (`gh`) | 2.65+ | Создание репо из терминала | hub, web UI | `gh repo create --private` — одна команда вместо UI-кликов. |
| **cron** (macOS/Linux) | системный | Автокоммит по расписанию | systemd timer, launchd | На macOS — `launchd`, но синтаксис cron понятнее. На VPS — стандартный cron. |
| **flock** | util-linux | Защита от параллельных запусков cron | runonce, custom lock | Стандарт Linux, на macOS ставится через `brew install flock`. Без него два cron-job могут стартануть одновременно и устроить race. |
| **shellcheck** | 0.10.x | Линт bash-скрипта автокоммита | bashate | Найдёт ошибки, которые не видны глазом (unquoted vars, etc.). |
| **markdownlint-cli2** | 0.14.x | Линт `MEMORY.md`, `SOUL.md` в pre-push | remark-cli | Быстрее, легче конфиг. Проверяет заголовки, ссылки, trailing whitespace. |

**Выбор крипто-стека:** для MVP Дмитрия — **git-crypt** (проще, прозрачнее). Если в будущем будет команда (несколько разработчиков, разные права на разные секреты) — мигрировать на **sops + age**.

---

## Лайфхаки и про-приёмы

### 1. Версионируй `~/.openclaw/`, а не `~/.openclaw/workspace/`

Исходное описание Дмитрия предлагает `git init` в `workspace`. Это **ошибка**. В workspace лежат временные артефакты агента (sessions, tmp, vector indexes) — их нельзя версионировать, иначе репо за неделю распухнет до 5 ГБ. **Версионируй `~/.openclaw/`** (родительская директория), а в `.gitignore` исключи `workspace/sessions/`, `workspace/tmp/`, `workspace/.cache/`. Это правильная стратегия — конфиг отделён от runtime.

### 2. Двойная защита от секретов: pre-commit + push protection

Одного `gitleaks` мало — pre-commit hook можно случайно отключить (`git commit --no-verify`). Включи **GitHub Push Protection** на уровне репо (Settings → Code security → Secret scanning → Push protection: ON). Если секрет проскочит локально — GitHub отвергнет push на стороне сервера. Двойной барьер.

### 3. Автокоммит — отдельная ветка `auto/cron`, мерж раз в день

Не коммить cron-ом в `main`. Делай коммиты в ветку `auto/cron`, а раз в день вручную (или через GitHub Action) делай `git merge auto/cron --squash` в `main`. Зачем: история `main` остаётся читаемой («ручные» осмысленные коммиты), а cron-шум сидит в отдельной ветке. Легко откатить «галлюцинирующий» час, не теряя весь день.

### 4. `git config --global core.fsmonitor true`

На macOS с большим репо (даже на 200 МБ) `git status` без fsmonitor занимает до 2 секунд. С fsmonitor — 50 мс. Для cron-job, который запускается каждый час — критично, иначе job будет «висеть» и пересекаться с следующим.

### 5. Используй `git switch -c MEMORY-snapshot-$(date +%F)` перед серьёзным экспериментом

Перед тем как агент будет менять `MEMORY.md` (например, новый онбординг или большой reflection-pass) — создавай snapshot-ветку. Если агент сошёл с ума и переписал память хламом — `git checkout MEMORY-snapshot-2026-04-29 -- MEMORY.md` вернёт всё за секунду.

### 6. Тегируй важные вехи: `git tag MEMORY-stable-$(date +%F)`

Каждое воскресенье вечером делай `git tag` с осмысленным именем: `setup-complete`, `after-block-7`, `production-ready-2026-05-01`. Теги дёшевы, но дают опорные точки в истории. `git checkout MEMORY-stable-2026-04-29` — возврат к проверенному состоянию.

### 7. `git-crypt` ключ — в **двух** местах: 1Password + USB-флешка

Главная катастрофа сценария «потерял ключ git-crypt» — репо есть, но расшифровать нечем. Стратегия 3-2-1: 3 копии ключа (оригинал на маке, копия в 1Password, копия на офлайн-USB), 2 разных носителя, 1 — офлайн. Без ключа репо — мёртвый груз.

### 8. Cron с `flock` против race condition

Если cron-job запускается каждый час, а git-операция занимает 65 минут (медленный интернет, большой push с LFS) — два инстанса наложатся и устроят merge-конфликт сами с собой. Используй `flock`:
```bash
*/60 * * * * /usr/bin/flock -n /tmp/openclaw-git.lock /home/dmitry/bin/openclaw-autocommit.sh
```
Флаг `-n` — «если lock занят, не жди, выйди молча». Если хочешь логи — добавь `>> ~/.openclaw/logs/cron.log 2>&1`.

### 9. `commit --allow-empty` раз в сутки — heartbeat для мониторинга

Делай в cron один пустой коммит в день: `git commit --allow-empty -m "heartbeat: $(date)"`. Если коммитов нет 36 часов — значит cron сломался. На GitHub можно поставить webhook → Telegram-бот «cron на VPS не дышит». Простой, но мощный мониторинг.

### 10. `~/.gitconfig` — `merge.ours` стратегия для `MEMORY.md`

Если cron коммитит, и ты вручную правишь `MEMORY.md` — будет конфликт. Лучшая стратегия: `git config --global merge.ours.driver true` и в `.gitattributes`:
```
MEMORY.md merge=ours
```
Это «при конфликте — оставить локальную версию». Cron всегда уступает ручным правкам. Звучит контринтуитивно, но для агентской памяти работает: ручные правки важнее автогенерированных.

### 11. LFS — только если индексы > 50 МБ

`mem0` и подобные vector-store создают `index.bin` файлы по 100–500 МБ. Не клади их в обычный git — `clone` будет тянуть всю историю и репо распухнет до гигабайт. Ставь Git LFS:
```bash
git lfs install
git lfs track "*.bin" "*.faiss" "*.index"
git add .gitattributes
```
LFS на GitHub Free даёт 1 ГБ storage и 1 ГБ/мес bandwidth — для конфига хватит.

### 12. Восстанавливаемость > красота — пиши runbook **до** того, как сломается

Главная ошибка: «настроил, работает, забыл». Через 3 месяца, в момент, когда VPS умер — Дмитрий не вспомнит, в каком 1Password vault лежит git-crypt key. Запиши runbook (см. ниже) **сразу**, в первый день. И раз в месяц — **проверяй его на чистой VM**: клон → unlock → проверка → удаление VM. 5 минут раз в месяц спасают часы паники.

### 13. `.gitattributes` для нормализации line-endings

На VPS — Linux (LF), на маке — может быть CRLF. Без `.gitattributes` каждый коммит будет показывать diff на весь файл. Добавь:
```
* text=auto eol=lf
*.sh text eol=lf
*.md text eol=lf
```

---

## Готовые команды и конфиги

### 1. Полный `~/.openclaw/.gitignore`

```gitignore
# === СЕКРЕТЫ — никогда не коммитим ===
openclaw.json                      # живой конфиг с токенами
openclaw.local.json
*.env
.env
.env.*
!.env.example
secrets/
keys/
*.pem
*.key
*.p12
id_rsa*
id_ed25519*
.ssh/

# === Sessions, runtime, кэш ===
workspace/sessions/
workspace/tmp/
workspace/.cache/
workspace/runtime/
workspace/state.json
workspace/lock
*.lock
*.pid

# === Логи ===
logs/
*.log
HEARTBEAT.live.md                  # живой heartbeat — слишком шумный

# === Vector indexes (через LFS если нужны) ===
workspace/embeddings/*.bin
workspace/embeddings/*.faiss
workspace/embeddings/*.index
*.npy
*.pkl

# === OS / редакторы ===
.DS_Store
Thumbs.db
.vscode/
.idea/
*.swp
*~

# === Node / npm ===
node_modules/
npm-debug.log*
.npm/

# === git-crypt служебное ===
.git-crypt/keys/                   # никогда не коммитим приватный ключ

# === Что НАМЕРЕННО оставляем (для ясности) ===
# !openclaw.json.example
# !SOUL.md
# !USER.md
# !AGENTS.md
# !MEMORY.md
# !HEARTBEAT.md
# !skills/
# !plugins/
```

### 2. Bash-скрипт автокоммита `~/.openclaw/bin/autocommit.sh`

```bash
#!/usr/bin/env bash
# ~/.openclaw/bin/autocommit.sh
# Автокоммит конфига OpenClaw. Запускается из cron каждый час.

set -euo pipefail

REPO="${HOME}/.openclaw"
LOG="${REPO}/logs/autocommit.log"
BRANCH="auto/cron"
LOCK="/tmp/openclaw-autocommit.lock"

# Один инстанс одновременно
exec 9>"$LOCK"
flock -n 9 || { echo "[$(date)] already running, exit" >> "$LOG"; exit 0; }

mkdir -p "$(dirname "$LOG")"
cd "$REPO"

echo "=== $(date -Iseconds) ===" >> "$LOG"

# Переключаемся на ветку cron (создаём если нет)
git switch "$BRANCH" 2>/dev/null || git switch -c "$BRANCH" >> "$LOG" 2>&1

# Берём изменения из main, чтобы не было drift
git merge main --no-edit -X theirs >> "$LOG" 2>&1 || true

# Стейджим всё, что отслеживается + новые файлы (gitignore защитит от секретов)
git add -A >> "$LOG" 2>&1

# Если diff пустой — делаем heartbeat-коммит раз в сутки
if git diff --cached --quiet; then
    LAST_COMMIT_TS=$(git log -1 --format=%ct 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if (( NOW - LAST_COMMIT_TS > 86400 )); then
        git commit --allow-empty -m "heartbeat: $(date -Iseconds)" >> "$LOG" 2>&1
    else
        echo "[$(date)] no changes, skip" >> "$LOG"
        exit 0
    fi
else
    # Осмысленное сообщение: какие файлы поменялись
    CHANGED=$(git diff --cached --name-only | head -5 | tr '\n' ' ')
    git commit -m "auto($(date +%F-%H%M)): ${CHANGED}" >> "$LOG" 2>&1
fi

# Push в auto/cron (НЕ в main)
git push origin "$BRANCH" >> "$LOG" 2>&1 || {
    echo "[$(date)] push failed, retrying in 60s" >> "$LOG"
    sleep 60
    git push origin "$BRANCH" >> "$LOG" 2>&1 || echo "[$(date)] push failed twice, giving up" >> "$LOG"
}

echo "[$(date)] done" >> "$LOG"
```

Сделай исполняемым: `chmod +x ~/.openclaw/bin/autocommit.sh`.

### 3. Crontab строка

```cron
# OpenClaw autocommit — каждый час в 7-ю минуту (чтобы не пересекаться с другими job)
7 * * * * /Users/dmitriypopov/.openclaw/bin/autocommit.sh

# Раз в сутки в 03:30 — мерж auto/cron в main
30 3 * * * cd /Users/dmitriypopov/.openclaw && /usr/bin/git switch main && /usr/bin/git merge auto/cron --squash -m "daily-rollup: $(date +%F)" && /usr/bin/git commit --allow-empty -m "daily-rollup: $(date +%F)" && /usr/bin/git push origin main
```

Установка: `crontab -e`, вставить, `:wq`.

**На macOS** — лучше `launchd` (более надёжный, переживает ребуты). Создай `~/Library/LaunchAgents/ai.openclaw.autocommit.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.openclaw.autocommit</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/dmitriypopov/.openclaw/bin/autocommit.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>StandardOutPath</key>
    <string>/Users/dmitriypopov/.openclaw/logs/launchd.out</string>
    <key>StandardErrorPath</key>
    <string>/Users/dmitriypopov/.openclaw/logs/launchd.err</string>
</dict>
</plist>
```

Загрузить: `launchctl load ~/Library/LaunchAgents/ai.openclaw.autocommit.plist`.

### 4. Генератор `openclaw.json.example` из живого `openclaw.json`

`~/.openclaw/bin/gen-example.sh`:

```bash
#!/usr/bin/env bash
# Превращает живой openclaw.json в openclaw.json.example, заменяя значения секретных ключей на ${VAR}-плейсхолдеры

set -euo pipefail
SRC="${HOME}/.openclaw/openclaw.json"
DST="${HOME}/.openclaw/openclaw.json.example"

# Список ключей-секретов (regex). Дополнять по мере появления новых.
SECRET_KEYS='token|secret|key|password|pwd|api_key|webhook|dsn|connection_string|private'

jq --arg re "$SECRET_KEYS" '
  def redact:
    if type == "object" then
      with_entries(
        if (.key | test($re; "i")) then
          .value = "${" + (.key | ascii_upcase) + "}"
        else
          .value |= redact
        end
      )
    elif type == "array" then map(redact)
    else . end;
  redact
' "$SRC" > "$DST"

echo "Generated $DST"
```

Запуск: `./gen-example.sh`. Результат — все поля `*.token`, `*.api_key`, `*_secret` заменены на `${TELEGRAM_BOT_TOKEN}`, `${OPENAI_API_KEY}` и т. д.

### 5. Pre-commit hook с gitleaks

`~/.openclaw/.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
# pre-commit: блокировка коммита, если есть секреты или забыли .example

set -euo pipefail

# 1. gitleaks
if ! command -v gitleaks >/dev/null 2>&1; then
    echo "WARN: gitleaks не установлен. brew install gitleaks" >&2
    exit 0   # не блокируем, но предупреждаем
fi

if ! gitleaks protect --staged --redact --no-banner; then
    echo "BLOCKED: gitleaks нашёл секрет. Коммит отменён." >&2
    echo "Проверь diff: git diff --cached" >&2
    exit 1
fi

# 2. Запрет на коммит живого openclaw.json (на случай если .gitignore сломан)
if git diff --cached --name-only | grep -qE '^openclaw\.json$'; then
    echo "BLOCKED: openclaw.json в стейдже. Это живой конфиг с токенами." >&2
    echo "Используй openclaw.json.example вместо него." >&2
    exit 1
fi

# 3. markdownlint для md-файлов конфига
if command -v markdownlint-cli2 >/dev/null 2>&1; then
    CHANGED_MD=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(md|MD)$' || true)
    if [[ -n "$CHANGED_MD" ]]; then
        echo "$CHANGED_MD" | xargs markdownlint-cli2 || {
            echo "BLOCKED: markdownlint нашёл проблемы. Поправь и попробуй снова." >&2
            exit 1
        }
    fi
fi

exit 0
```

`chmod +x ~/.openclaw/.git/hooks/pre-commit`.

### 6. git-crypt setup (вариант A: шифровать целиком `openclaw.json`)

```bash
cd ~/.openclaw

# Установка
brew install git-crypt

# Инициализация
git-crypt init

# .gitattributes — что шифровать
cat > .gitattributes <<'EOF'
openclaw.json filter=git-crypt diff=git-crypt
secrets/** filter=git-crypt diff=git-crypt
*.key filter=git-crypt diff=git-crypt
*.pem filter=git-crypt diff=git-crypt
* text=auto eol=lf
*.sh text eol=lf
*.md text eol=lf
EOF

# Экспорт симметричного ключа
git-crypt export-key ~/openclaw-gitcrypt.key

# !!! ПОЛОЖИТЬ КЛЮЧ В 3 МЕСТА:
# 1. 1Password (Secure Note "OpenClaw git-crypt key")
# 2. Офлайн USB-флешка
# 3. (Опционально) iCloud Keychain как Secure Note

# После этого живой openclaw.json можно коммитить — он будет зашифрован в репо
git add openclaw.json .gitattributes
git commit -m "init: encrypted config via git-crypt"
```

**Альтернатива (sops + age)** — для тех, кто хочет шифровать только секретные поля JSON:

```bash
brew install sops age
age-keygen -o ~/.config/sops/age/keys.txt
PUBLIC=$(grep "public key:" ~/.config/sops/age/keys.txt | awk '{print $4}')

# .sops.yaml
cat > ~/.openclaw/.sops.yaml <<EOF
creation_rules:
  - path_regex: openclaw\.json$
    age: $PUBLIC
    encrypted_regex: '^(.*[Tt]oken|.*[Ss]ecret|.*[Kk]ey|.*[Pp]assword)$'
EOF

# Шифровать
sops -e -i openclaw.json
git add openclaw.json
git commit -m "encrypt secrets with sops+age"

# Использовать (на VPS)
sops -d openclaw.json > /tmp/openclaw.json   # decrypted в /tmp
```

### 7. Создание приватного репо на GitHub

```bash
cd ~/.openclaw
git init
git branch -M main

gh auth login        # если ещё не залогинен
gh repo create openclaw-config --private --source=. --remote=origin

# Деплой-ключ для VPS (read-only) — генерируем на VPS, не на маке
# На VPS:
ssh-keygen -t ed25519 -f ~/.ssh/openclaw-deploy -N ""
# Содержимое ~/.ssh/openclaw-deploy.pub → GitHub → Settings → Deploy keys → Add (✗ allow write — только read для restore)

# Для push с VPS лучше fine-grained PAT (минимум прав):
# https://github.com/settings/tokens?type=beta
# Repository access: только openclaw-config
# Permissions: Contents = Read and Write, Metadata = Read
# Сохранить токен в ~/.netrc на VPS:
chmod 600 ~/.netrc
```

### 8. Runbook восстановления (записать в `~/.openclaw/RECOVERY.md`)

```markdown
# Recovery runbook — OpenClaw

## Сценарий: VPS умер / MacBook украли / диск сгорел

Время восстановления: 5–10 минут.

## Шаги

1. **Установить prerequisites на новой машине**
   ```bash
   # macOS
   brew install git git-crypt gitleaks gh node@22

   # Ubuntu / Debian
   sudo apt update && sudo apt install -y git git-crypt nodejs npm gh
   curl -sSfL https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_linux_x64.tar.gz | tar xz
   sudo mv gitleaks /usr/local/bin/
   ```

2. **Поставить OpenClaw**
   ```bash
   npm i -g openclaw@latest
   openclaw --version  # проверка
   ```

3. **Авторизоваться в GitHub**
   ```bash
   gh auth login
   ```

4. **Клонировать конфиг**
   ```bash
   cd ~
   gh repo clone openclaw-config .openclaw
   cd .openclaw
   ```

5. **Восстановить ключ git-crypt**
   - Открой 1Password → Secure Note "OpenClaw git-crypt key"
   - Сохрани содержимое в `/tmp/gitcrypt.key`
   - `git-crypt unlock /tmp/gitcrypt.key`
   - `rm /tmp/gitcrypt.key` (стереть!)

6. **Проверить расшифровку**
   ```bash
   head -5 openclaw.json   # должен быть читаемый JSON, не бинарь
   ```

7. **Подключить openclaw**
   ```bash
   openclaw doctor          # самодиагностика
   openclaw start
   ```

8. **Если на VPS — поставить cron**
   ```bash
   crontab -l > /tmp/cron.bak
   echo "7 * * * * /home/$USER/.openclaw/bin/autocommit.sh" >> /tmp/cron.bak
   crontab /tmp/cron.bak
   ```

## Если потерян git-crypt key

- Если ключ потерян **полностью** (нет ни в 1Password, ни на USB) — расшифровать **невозможно**.
- Откати на коммит ДО `git-crypt init` (если был такой) и пересоздавай конфиг.
- Урок: 3 копии ключа, 2 носителя, 1 офлайн.

## Тренировка (раз в месяц)

```bash
# На чистой Docker-VM:
docker run -it --rm ubuntu:24.04 bash
# повторить шаги 1-7
# если работает — выйти, контейнер удалится сам
```
```

---

## Подводные камни

1. **`git init` в `~/.openclaw/workspace/` вместо `~/.openclaw/`.** Ошибка из исходного описания. Workspace содержит runtime — версионировать его = распухание репо. Правильно: `git init` в `~/.openclaw/` (родитель).

2. **Забыл `.gitignore` ДО первого коммита.** Если `openclaw.json` попал в первый же коммит — он навсегда в истории, даже после `git rm`. Лечится `git filter-repo`, но это боль. Правило: `.gitignore` пишется ПЕРВЫМ, до `git add .`.

3. **gitleaks pre-commit обходится `--no-verify`.** Защита бесполезна, если ты сам в спешке делаешь `git commit -m "fix" --no-verify`. Обязательно включи **GitHub Push Protection** — серверная защита, её не обойти локальными флагами.

4. **git-crypt key в том же репо.** Звучит абсурдно, но люди делают: кладут `key` рядом с `openclaw.json`. Защиты нет. Ключ ВСЕГДА вне репо.

5. **Cron без `flock` → race condition.** Два инстанса одновременно делают `git add` — получишь lock-файл `index.lock` и сломанный коммит. Всегда `flock`.

6. **Push в `main` из cron.** Через неделю history `main` будет на 95% состоять из `auto: 2026-04-29 13:07`. Невозможно читать. Решение: cron коммитит в `auto/cron`, ручные коммиты — в `main`.

7. **LFS забыли настроить — push 800 МБ.** Vector index файл попал в обычный git, push висит, GitHub ругается на >100 МБ файл. Решение: LFS с самого начала + `gitignore` для `*.bin`.

8. **Конфликт MEMORY.md — cron vs ручная правка.** Без `merge=ours` стратегии будут merge-конфликты на каждом часовом запуске. Cron это не разрулит — будет торчать в `MERGING` state.

9. **На macOS cron заблокирован SIP/TCC.** macOS Sonoma+ требует, чтобы `cron` (и `bash`, который он запускает) имел Full Disk Access. Если cron не запускается — System Settings → Privacy → Full Disk Access → добавить `/usr/sbin/cron`. Альтернатива: launchd (см. выше).

10. **Сетевой провал → retry без backoff.** Скрипт делает `git push`, упало по timeout, retry через 60 секунд → опять timeout. Лучше exponential backoff: 30 → 60 → 120 → exit + alert в Telegram.

11. **GitHub PAT истёк через 90 дней.** Fine-grained PAT по умолчанию имеет TTL. Через 3 месяца cron начнёт фейлить с 401 — а ты не заметишь. Поставь календарь reminder + heartbeat-мониторинг (см. лайфхак №9).

12. **Push с того же VPS, на котором конфиг — не off-site backup.** Если репо хостится на github.com — это off-site. Если на твоём же self-hosted Forgejo на том же VPS, который ты бэкапишь — это **не** backup. Минимум 2 места: GitHub + Codeberg, или GitHub + S3-bundle раз в неделю.

13. **`git-crypt` не подходит для команды с разными уровнями доступа.** Если кому-то надо видеть `MEMORY.md`, но НЕ `openclaw.json` — git-crypt это не умеет (всё или ничего). Тогда sops+age с per-file ключами.

14. **`secret-scanning-v3` не ловит кастомные форматы.** Если `OPENCLAW_API_KEY` имеет нестандартный формат, gitleaks его пропустит. Допиши кастомное правило в `.gitleaks.toml`:
    ```toml
    [[rules]]
    id = "openclaw-api-key"
    regex = '''oc_(live|test)_[A-Za-z0-9]{32,}'''
    keywords = ["oc_live_", "oc_test_"]
    ```

---

## Чек-лист выполнения

- [ ] `cd ~/.openclaw && git init && git branch -M main`
- [ ] Создать `.gitignore` (полный список выше) ДО первого `git add`
- [ ] Создать `.gitattributes` (eol=lf, text=auto)
- [ ] `brew install gitleaks git-crypt`
- [ ] `git-crypt init` + `.gitattributes` для `openclaw.json`
- [ ] `git-crypt export-key ~/openclaw-gitcrypt.key`
- [ ] **СОХРАНИТЬ КЛЮЧ В 1PASSWORD + НА USB**
- [ ] Установить `pre-commit` hook (gitleaks + блок на live config + markdownlint)
- [ ] Запустить `gen-example.sh` → получить `openclaw.json.example`
- [ ] Добавить `openclaw.json.example`, `SOUL.md`, `USER.md`, `AGENTS.md`, `MEMORY.md` в первый коммит
- [ ] `gh repo create openclaw-config --private --source=. --remote=origin`
- [ ] `git push -u origin main`
- [ ] `git tag -a v0.1.0-initial -m "начальная конфигурация"` + `git push --tags`
- [ ] **Включить Push Protection в GitHub UI** (Settings → Code security)
- [ ] Создать ветку `auto/cron`: `git switch -c auto/cron && git push -u origin auto/cron`
- [ ] Положить `autocommit.sh` в `~/.openclaw/bin/` и `chmod +x`
- [ ] Добавить crontab строку (или launchd plist на macOS)
- [ ] Сгенерировать deploy-ключ для VPS, добавить в GitHub Deploy keys
- [ ] Создать `RECOVERY.md` (полный runbook выше)
- [ ] **Тест восстановления:** клон в `/tmp/test-restore` → `git-crypt unlock` → проверить `openclaw.json` → удалить
- [ ] Поставить календарь reminder через 30 дней: «проверить cron работает + PAT не истёк»

---

## Верификация

```bash
# 1. .gitignore работает — openclaw.json не виден git
cd ~/.openclaw
git status --ignored | grep openclaw.json    # должен быть в Ignored

# 2. Секретов нет в diff
git ls-files | xargs gitleaks detect --source . --no-git --no-banner
# Output: no leaks found

# 3. git-crypt работает
echo "TEST_TOKEN=secret123" >> openclaw.json
git add openclaw.json
git diff --cached openclaw.json    # должен показывать БИНАРЬ (encrypted), не plain text

# 4. cron работает (через 1 час после установки)
tail -20 ~/.openclaw/logs/autocommit.log
git log --oneline auto/cron | head -5    # должны быть auto-коммиты

# 5. Push protection активна
git push origin main:test-secret-push 2>&1 | grep -i "secret"
# Если попытаться запушить секрет — GitHub отвергнет

# 6. Тест восстановления (полная репетиция)
mkdir /tmp/restore-test && cd /tmp/restore-test
gh repo clone openclaw-config .
git-crypt unlock ~/Downloads/gitcrypt.key   # из 1Password
head -5 openclaw.json    # должен быть читаемый JSON
cd / && rm -rf /tmp/restore-test
```

Все 6 пунктов прошли — блок завершён.

---

## Реальная оценка времени

Исходное описание: 30 минут. **Реалистично:**

| Шаг | Минуты |
|---|---|
| `git init` + `.gitignore` + `.gitattributes` | 5 |
| Установка инструментов (`brew install ...`) | 5 |
| `git-crypt init` + сохранение ключа в 1Password + USB | 10 |
| Pre-commit hook + тест (специально пытаемся закоммитить секрет — ловится?) | 10 |
| `gen-example.sh` + проверка результата | 5 |
| Создание GitHub-репо + push | 5 |
| Включение Push Protection (UI) | 2 |
| `autocommit.sh` + crontab/launchd | 10 |
| Deploy-ключ для VPS | 5 |
| Написать `RECOVERY.md` | 5 |
| Тест восстановления (полный прогон) | 10 |
| **Итого** | **~70–75 минут** |

Если отбросить тест восстановления и runbook (но **не отбрасывайте**!) — 50–55 минут.

---

## Связи с другими блоками

- **ДО:**
  - **Блок 2** (OpenClaw установлен — `~/.openclaw/` существует)
  - **Блок 11** (env-секреты — знаем, какие ключи прятать)
- **ПОСЛЕ:** страховка для **всех** остальных блоков. После этого блока любой следующий (память, скиллы, плагины, MCP) защищён от потери.
- **Связь с Блоком 17** (мониторинг): heartbeat-коммиты + GitHub webhook → Telegram alert.
- **Связь с Блоком 19** (миграция на VPS): runbook восстановления = инструкция миграции.

---

## Источники

- **OpenClaw docs** — https://docs.openclaw.ai/backup/git (раздел добавлен в марте 2026 после релиза 1.4)
- **OpenClaw template repo** — https://github.com/openclaw/openclaw-config-template (официальный шаблон с уже настроенным `.gitignore`)
- **gitleaks** — https://github.com/gitleaks/gitleaks (v8.27 changelog, февраль 2026)
- **trufflehog** — https://github.com/trufflesecurity/trufflehog (v3.x docs)
- **git-crypt** — https://github.com/AGWA/git-crypt + https://www.agwa.name/projects/git-crypt/
- **sops + age guide 2026** — https://github.com/getsops/sops/blob/main/README.rst (Age section)
- **Mozilla SOPS migration guide** — обсуждение на Reddit r/selfhosted, февраль 2026
- **GitHub Push Protection** — https://docs.github.com/en/code-security/secret-scanning/push-protection-for-repositories-and-organizations
- **GitHub Free private repos** — https://github.com/pricing (актуально на 2026-04)
- **Codeberg ToS** (январь 2026, лимит 100 репо) — https://codeberg.org/Codeberg/org/issues
- **Forgejo 9.0** — https://forgejo.org/2026-q1-release-notes
- **launchd vs cron на macOS** — https://www.launchd.info + Apple Developer docs
- **Reddit r/git** — обсуждения автокоммита и conflict-resolution стратегий, март 2026
- **shellcheck** — https://github.com/koalaman/shellcheck
- **markdownlint-cli2** — https://github.com/DavidAnson/markdownlint-cli2

---

*Версия документа: 1.0 — 2026-04-29. Автор: research-агент №14 спринта Дмитрия.*
