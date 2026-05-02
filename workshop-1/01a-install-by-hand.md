# 🛠 План Б — Установка OpenClaw полностью руками (без AI)

> Для тех, кто **не хочет связываться с AI-плагином** на этапе установки.
> Только Mac Terminal + SSH + копи-паста команд.
>
> **Время**: ~45 минут.
> **Результат**: бот в Telegram отвечает на «привет» через MiniMax M2.7.

---

## ⚖️ Когда использовать этот план вместо `01-prompts.md`

| Используй гибридный путь (`01-prompts.md`) | Используй этот план Б |
|---|---|
| ✅ У тебя есть Antigravity + AI-плагин работающий | ❌ Antigravity не установлен или AI-плагин не работает |
| ✅ Хочешь чтобы AI делал рутину | ❌ Не доверяешь AI на этапе установки |
| ✅ Готов пройти 11 промптов | ❌ Хочешь полный контроль команд |

**Оба пути приводят к одинаковому результату.** Это просто разные способы.

---

## 📝 ЭТАП 0 — Подготовка значений (Mac, 5 минут)

В Notes на маке заведи запись «OpenClaw spring» с **9 значениями**:

```
═══ VPS ═══
VPS_IP        = ___________________
ROOT_PASSWORD = ___________________

═══ API-ключи ═══
MINIMAX_API_KEY    = sk-___
DEEPSEEK_API_KEY   = sk-___
OPENROUTER_API_KEY = sk-or-___
GROQ_API_KEY       = gsk____
OPENAI_API_KEY     = sk-___

═══ Telegram ═══
TELEGRAM_BOT_TOKEN = 7891___:AAH___
TELEGRAM_USER_ID   = 241873189
```

Открой **Mac Terminal** (Spotlight → «Terminal»).

---

## 🔑 ЭТАП 1 — Создать SSH-ключ (Mac, 2 минуты)

```bash
# Удалить старый если был
rm -f ~/.ssh/clawd_ed25519 ~/.ssh/clawd_ed25519.pub

# Создать новый, без пароля
ssh-keygen -t ed25519 -f ~/.ssh/clawd_ed25519 -C "clawd@vps" -N ""

# Показать публичный ключ (скопируй в Notes)
cat ~/.ssh/clawd_ed25519.pub
```

Скопируй вывод (начинается с `ssh-ed25519 AAAA...`) в Notes.

---

## 🔌 ЭТАП 2 — Подключение к VPS как root (3 минуты)

```bash
ssh root@VPS_IP
```

Введи `ROOT_PASSWORD` из Notes.

Должна открыться сессия `root@vps:~#`.

### Скопировать твой публичный ключ в authorized_keys

На VPS, **замени** строку `ssh-ed25519 AAAA...` на твой публичный ключ из Notes:

```bash
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "ssh-ed25519 AAAA... clawd@vps" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo "✓ ключ добавлен"
```

Не выходи из SSH — продолжаем как root.

---

## 🛡 ЭТАП 3 — VPS hardening (10 минут, как root)

### 3.1 Обновить систему

```bash
apt update && apt upgrade -y
```

### 3.2 Создать пользователя clawd

```bash
adduser --disabled-password --gecos "" clawd
usermod -aG sudo clawd
echo "✓ clawd создан"
```

### 3.3 ⚠️ КРИТИЧНО — Passwordless sudo (ДО блокировки root!)

```bash
echo "clawd ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/clawd
chmod 440 /etc/sudoers.d/clawd

# Проверить что работает
su - clawd -c "sudo -n whoami"
```

**Должно вывести**: `root`

⛔ **Если ответило не `root`** — СТОП, не продолжай. Иначе после блокировки root SSH потеряешь доступ.

### 3.4 Скопировать SSH-ключ в clawd

```bash
mkdir -p /home/clawd/.ssh
cp /root/.ssh/authorized_keys /home/clawd/.ssh/
chown -R clawd:clawd /home/clawd/.ssh
chmod 700 /home/clawd/.ssh
chmod 600 /home/clawd/.ssh/authorized_keys
echo "✓ ключ скопирован"
```

### 3.5 Заблокировать root SSH

```bash
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
grep -E "^PermitRootLogin|^PasswordAuthentication" /etc/ssh/sshd_config
```

Должно показать:
```
PermitRootLogin no
PasswordAuthentication no
```

### 3.6 ufw firewall

```bash
ufw default deny incoming
ufw default allow outgoing
ufw limit 22/tcp comment 'SSH rate-limited'
ufw --force enable
ufw status
```

### 3.7 fail2ban

```bash
apt install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban
systemctl is-active fail2ban
```

### 3.8 Swap 4GB

```bash
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
swapon --show
```

### 3.9 unattended-upgrades

```bash
apt install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' > /etc/apt/apt.conf.d/52unattended-upgrades-local
systemctl enable unattended-upgrades
echo "✓ автообновления настроены"
```

### 3.10 Linger для clawd

```bash
loginctl enable-linger clawd
loginctl show-user clawd | grep Linger
```

Должно: `Linger=yes`

### 3.11 Выйти из root

```bash
exit
```

---

## 🟢 ЭТАП 4 — Подключение как clawd (1 минута)

В Mac Terminal:

```bash
# ⚠️ 91.234.56.78 — это ПРИМЕР! Замени на свой реальный IP VPS:
ssh -i ~/.ssh/clawd_ed25519 clawd@91.234.56.78
```

Должна открыться сессия `clawd@vps:~$` **БЕЗ пароля**.

⚠️ Если оставишь в команде слово `VPS_IP` буквально — получишь ошибку `Could not resolve hostname vps_ip`. Это плейсхолдер, его надо заменить на свой реальный IP!

```bash
sudo -n whoami
# Должно: root
```

---

## 🟢 ЭТАП 5 — Node 22 + npm prefix (5 минут)

```bash
# nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# Подгрузить в текущую сессию
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Node 22
nvm install 22
nvm use 22
nvm alias default 22

node --version    # v22.x.x

# npm prefix без sudo
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'

# PATH в три файла (для cron/systemd тоже)
echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc
echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.profile
echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bash_profile

export PATH=$HOME/.npm-global/bin:$PATH
echo $PATH | tr ':' '\n' | head -3
```

В первой строке должно быть `/home/clawd/.npm-global/bin`.

---

## 📦 ЭТАП 6 — Установка OpenClaw (3 минуты)

```bash
npm i -g openclaw

openclaw --version    # 2026.4.29 или новее
which openclaw        # /home/clawd/.npm-global/bin/openclaw
```

---

## 🧙 ЭТАП 7 — `openclaw onboard` интерактивно (10 минут) ⭐

**Главный шаг.** Интерактивный мастер.

```bash
openclaw onboard
```

### 📋 Cheat-sheet ответов

| # | Вопрос мастера | Ответ |
|---|---|---|
| 1 | Welcome / continue? | **Enter** |
| 2 | Mode? | **local** |
| 3 | Flow? | **quickstart** |
| 4 | **Authentication mode?** | **token** ⚠️ (НЕ skip!) |
| 5 | Gateway bind? | **loopback** |
| 6 | Gateway port? | **18789** |
| 7 | **Enable device-pair plugin?** | **yes** ⚠️ |
| 8 | Configure providers? | **yes** |
| 9 | Add MiniMax? | yes → `MINIMAX_API_KEY` |
| 10 | Add DeepSeek? | yes → `DEEPSEEK_API_KEY` |
| 11 | Add OpenRouter? | yes → `OPENROUTER_API_KEY` |
| 12 | Add Groq? | yes → `GROQ_API_KEY` |
| 13 | Add OpenAI? | yes → `OPENAI_API_KEY` |
| 14 | Default primary model? | **minimax/MiniMax-M2.7** ⚠️ заглавные! |
| 15 | Configure channels? | **yes** |
| 16 | Channel type? | **telegram** |
| 17 | Telegram bot token? | `TELEGRAM_BOT_TOKEN` |
| 18 | Channel name? | **main** |
| 19 | dmPolicy? | **allowlist** |
| 20 | Allow from user IDs? | `TELEGRAM_USER_ID` |
| 21 | Install skills now? | **skip** |
| 22 | Install systemd-user service? | **yes** |
| 23 | Enable linger? | **yes** |
| 24 | Start daemon now? | **yes** |
| 25 | Run doctor? | **yes** |
| 26 | Save config? | **yes** |

**Если мастер задал вопрос не из таблицы** → Ctrl+C, открой
`knowledge-base/CONSULTANT-PROMPT.md`, спроси у консультанта, потом запусти
`openclaw onboard` снова.

---

## ✅ ЭТАП 8 — Проверка (1 минута)

```bash
openclaw devices list           # запись с operator.admin
openclaw models status          # 5 ✓
openclaw channels list          # telegram main active
openclaw doctor --deep | tail   # 0 critical
systemctl --user status openclaw --no-pager | head -10
```

---

## 🤖 ЭТАП 9 — «Привет» в Telegram (1 минута)

В Telegram → найди бота → пиши «Привет!»

В SSH-сессии:
```bash
openclaw logs --since 30s
```

Найди `model=minimax/MiniMax-M2.7 ok` — победа.

---

## 🎯 После Этапа 9

У тебя живой базовый бот. Дальше — **тонкие настройки**, которые удобно
делать через AI-плагин в Antigravity (но если очень хочется — можно тоже
руками):

1. **Alias premium / think** — для команды `/premium` и reasoning
2. **Watchdog cron** — kill-switch если расход > $3/час
3. **Картинки** — `imageGenerationModel.primary` + tools.profile
4. **SOUL.md** — личность, характер, anti-sycophancy правила

См. `01-prompts.md` промпты 7-10 — там готовые промпты для AI который
эти 4 шага сделает за тебя.

---

## 🆘 Если упало на любом этапе

1. Открой `knowledge-base/CONSULTANT-PROMPT.md`
2. Скопируй в новый чат AI (Claude.ai в браузере подойдёт)
3. Опиши проблему — получишь точный фикс из базы знаний

Топ-5 ловушек:
- `1008 pairing required` → device-pair плагин выключен или onboard auth=skip
- `openclaw: command not found` из cron → PATH не в ~/.profile
- Бот через DeepSeek а не MiniMax → slug в нижнем регистре, должен `MiniMax-M2.7`
- Daemon после reboot не стартует → `loginctl enable-linger` не сделан
- $4200/63ч runaway → fallback модель ДОРОЖЕ primary, поменяй

---

## ⏱ Тайминг этапов

| Этап | Время |
|---|---|
| 0. Подготовка Notes | 5 мин |
| 1. SSH-ключ | 2 мин |
| 2. Подключение root | 3 мин |
| 3. VPS hardening | 10 мин |
| 4. Подключение clawd | 1 мин |
| 5. Node 22 + npm | 5 мин |
| 6. npm i openclaw | 3 мин |
| 7. **openclaw onboard** | 10 мин |
| 8. Проверки | 1 мин |
| 9. «Привет» | 1 мин |
| **Итого** | **~41 мин** |

После Этапа 9 → переходи к `02-self-check.md` (8 запросов в Telegram-бот) →
`03-audit.md` (независимый аудит).
