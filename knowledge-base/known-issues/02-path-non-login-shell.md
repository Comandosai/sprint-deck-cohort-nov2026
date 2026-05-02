# PATH в non-login shell — `openclaw: command not found` из cron/SSH

> **Симптом**: `openclaw` работает в обычной SSH-сессии, но из cron / systemd / `ssh user@host 'команда'` падает с `bash: openclaw: command not found`.

---

## 🩺 Диагноз

`npm config set prefix '~/.npm-global'` кладёт бинарь в `~/.npm-global/bin/openclaw`. Этот путь добавляется в `$PATH` **только** через `~/.bashrc`.

Но:
- `~/.bashrc` грузится **только в interactive non-login shell** (когда ты вошёл по SSH и набираешь команды)
- `cron` запускает скрипты **в non-interactive non-login shell** → `~/.bashrc` НЕ грузится → PATH без `~/.npm-global/bin`
- `ssh user@host 'команда'` (с командой в кавычках) — **non-interactive non-login** → то же самое
- `systemd-user` сервис — берёт PATH из `Environment=` или дефолт системы

Проверка:
```bash
ssh clawd@VPS 'echo $PATH'
# Скорее всего НЕ видишь /home/clawd/.npm-global/bin

ssh clawd@VPS 'bash -lc "echo \$PATH"'
# С -lc видишь — потому что -l = login shell, грузит .profile
```

## ✅ Фикс — PATH в три файла

```bash
# Кладём export в три места — для всех вариантов shell:
echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc        # interactive
echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.profile       # login non-interactive
echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bash_profile  # macOS-style login
```

**Зачем все три**: разные дистрибутивы Ubuntu / разные shell-настройки читают разные файлы. Положить в три — гарантированно работает везде.

## 🛠 Альтернатива: использовать `bash -lc` в команде

Если поправить файлы нельзя — оборачивать команду в `bash -lc`:
```bash
# Не работает:
ssh clawd@VPS 'openclaw doctor'

# Работает:
ssh clawd@VPS 'bash -lc "openclaw doctor"'
```

`-l` = login shell → грузит `.profile` и `.bash_profile`.

## 🐛 Где это кусает в реальности

### 1. Watchdog cron
```bash
# /home/clawd/.openclaw/scripts/watchdog.sh
#!/bin/bash
openclaw spend --json   # ← упадёт command not found
```

**Фикс**: добавить export в первой строке после shebang:
```bash
#!/bin/bash
export PATH=$HOME/.npm-global/bin:$PATH    # ← обязательно!
openclaw spend --json
```

### 2. AI-агент диагностика через SSH
AI запускает `ssh clawd@VPS 'openclaw doctor'` через свой Bash-инструмент → command not found → AI думает что openclaw сломан.

**Фикс**: AI должен использовать `bash -lc` обёртку:
```bash
ssh clawd@VPS 'bash -lc "openclaw doctor --deep | tail -60"'
```

В Промпте 0 (meta) v1.5+ это прописано:
```
PATH ЛОВУШКА В non-login shell:
Для одноразовых SSH-команд используй: ssh ... 'bash -lc "openclaw ..."'
```

### 3. systemd-user сервис
По умолчанию systemd-user берёт минимальный PATH. Если `openclaw onboard --systemd-user` сгенерил unit без `Environment="PATH=..."` — daemon не запустится.

**Фикс**: в `~/.config/systemd/user/openclaw.service` добавить:
```ini
[Service]
Environment="PATH=/home/clawd/.npm-global/bin:/usr/local/bin:/usr/bin:/bin"
```

(Хотя обычно `openclaw onboard` сам это прописывает корректно.)

## 🔍 Как проверить что PATH везде

```bash
# 1. Interactive
echo $PATH | grep npm-global    # должен показать /home/clawd/.npm-global/bin

# 2. Non-login non-interactive (как cron)
ssh clawd@VPS '/bin/bash -c "echo \$PATH"' | grep npm-global

# 3. Login (с -lc)
ssh clawd@VPS 'bash -lc "echo \$PATH"' | grep npm-global

# 4. Cron-environment симуляция
env -i bash -c '. ~/.bashrc; echo $PATH'   # должен подхватить через .bashrc
env -i bash -lc 'echo $PATH'               # должен подхватить через .profile
```

Все 4 проверки должны показать `/home/clawd/.npm-global/bin`.

## 🛡 Профилактика

В Промпте 5 v1.5+ явно:
```
⚠️ PATH в ТРИ файла (КРИТИЧНО для cron/systemd/non-login shell):
  echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc
  echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.profile
  echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bash_profile
```

И в Промпте 8 (watchdog) первой строкой скрипта:
```bash
export PATH=$HOME/.npm-global/bin:$PATH
```

## 📚 Связанные

- `01-1008-pairing-required.md` — главная ошибка установки
- `08-onboard-skip-bootstrap.md` — почему `--non-interactive` ломает onboard
