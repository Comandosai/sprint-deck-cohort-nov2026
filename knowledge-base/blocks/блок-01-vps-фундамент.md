# Блок 1: VPS-фундамент

> **Что:** базовая подготовка чистого Linux-VPS под установку OpenClaw (пользователь, SSH, swap, Node 22/24, firewall, fail2ban, автообновления).
> **Зачем:** чтобы `npm i -g openclaw` не упал на OOM, чтобы 22-й порт не сорвали ботнеты в первые 12 часов, и чтобы дальше Блок 2 (онбординг OpenClaw) встал «как по маслу».
> **Время:** 35–55 минут с проверками. Если делаешь впервые и читаешь — закладывай 90 минут.

---

## Цель блока

Получить голый Ubuntu 24.04 LTS, доведённый до состояния «production-ready под одного пользователя `clawd`»: с ключами вместо паролей, swap-ом, который вытягивает пиковую нагрузку `npm install` и сборки нативных модулей под Node 22/24, минимальным firewall (только 22/tcp, причём с rate-limit), активным fail2ban с recidive-jail и unattended-upgrades, который ставит **только** security-патчи без ребута в 3 ночи посреди прод-сессии.

После этого блока ты сможешь спокойно делать `curl -fsSL https://openclaw.ai/install.sh | bash` и `openclaw onboard --install-daemon` — daemon (Gateway) поднимется на `127.0.0.1:18789`, не торчит наружу, переживает logout по SSH (через `loginctl enable-linger`) и при этом сервер защищён от типового перебора паролей и от установки пакета, в котором завтра обнаружат CVE.

Ключевое отличие от «обычной подготовки VPS под Node-приложение» — у OpenClaw daemon живёт как **systemd --user** сервис от имени `clawd`, а не как root-сервис. Это сильно меняет схему лимитов (LimitNOFILE через `~/.config/systemd/user.conf.d/`, а не `/etc/systemd/system.conf`), запуск без логина (lingering), и хранение `~/.openclaw/openclaw.json` с токенами/API-ключами под `chmod 600`.

---

## Что нового в апреле 2026

- **Node.js 24 LTS** (стал LTS 28 октября 2025) — поддержка до апреля 2028. Включает npm v11 (на 65% быстрее установок, чем v10), стабильный встроенный TypeScript-runner, OpenSSL 3.5 с security-level 2 (RSA <2048 запрещены).
- **Node.js 22 LTS** — Active LTS до апреля 2027. Минимум для OpenClaw — **22.14**, а в реальности `openclaw doctor` ругается уже на <22.16. Для прода в апреле 2026 годятся оба, но **под OpenClaw официально рекомендуется Node 24** (см. `docs.openclaw.ai/install`).
- **Ubuntu 24.04.x LTS «Noble Numbat»** — обновлён до 24.04.4. Поддержка ядра 6.8/6.11 HWE, fail2ban в репах теперь по дефолту с `backend = systemd` (журнал systemd, без `/var/log/auth.log`). Это ломает старые гайды, где пишут `logpath = /var/log/auth.log`.
- **Hetzner подняла цены 1 апреля 2026** — CX22 (2 vCPU/4 GB/40 GB) теперь ~€4.99, CPX22 (2 vCPU AMD/4 GB/80 GB NVMe) ~€7.99. Всё равно дешевле DO/Vultr примерно в 2–2.5×.
- **OpenClaw v2026.3.7+** — известный регресс: `openclaw-message` течёт памятью на 4 GB-серверах. Issue #41778. Лечится либо `NODE_OPTIONS="--max-old-space-size=2048"`, либо откатом на v2026.3.2, либо апгрейдом до v2026.3.24+.
- **OpenClaw v2026.3.23-2** — баг #53547: bootstrap-файлы (SOUL.md, AGENTS.md и т.д.) не подхватываются из workspace, ищутся в `node_modules/.../templates/`. Если первый запуск выглядит «как будто без личности» — это оно, апгрейднись.
- **Что устарело:**
  - `apt install nodejs` без NodeSource — даёт Node 18 в 24.04, **не годится** для OpenClaw.
  - Пароли в `sshd_config` — отключаем сразу, без вариантов.
  - `iptables-save`-ручные правила — уже несколько лет проигрывают `ufw` или `nftables` по UX. Под OpenClaw — `ufw` достаточно.
  - `fail2ban` `backend = polling` или `backend = auto` — на 24.04 явно прописываем `backend = systemd`.
  - `ssh-keygen -t rsa -b 2048` — слишком короткий. RSA-4096 ещё ОК, но **ed25519 — стандарт 2026**.

---

## Конкретные инструменты и версии

| Инструмент | Версия (апрель 2026) | Зачем | Альтернатива | Выбор и почему |
|---|---|---|---|---|
| ОС | Ubuntu 24.04.4 LTS | Совместима с Node 22/24, родной systemd 255, fail2ban 1.0.2, поддержка до 2029 | Debian 12 «Bookworm», Ubuntu 22.04 | Ubuntu 24.04 — LinuxCapable, RamNode и Hetzner все используют её в OpenClaw-гайдах. На Debian 12 systemd 252 и старее nodejs в репе, придётся всё через NodeSource. |
| Node.js | **24.x LTS** (рекомендация OpenClaw), либо 22.16+ | Runtime OpenClaw daemon | 22 LTS, Bun (не работает с MCP) | Node 24 — npm v11 быстрее, OpenSSL 3.5, дольше LTS-окно. Node 22 — если хочется максимально консервативно. |
| Менеджер Node | **fnm** (Rust) или NodeSource apt | Установка/смена версий | nvm (bash, медленный), volta, asdf | На сервере под одного юзера `clawd` лучше **NodeSource apt** — простой systemd-PATH, никаких bash-инициализаций. fnm — если планируешь жонглировать версиями (Node 22 для одного агента, 24 для другого). |
| Swap | **swapfile 4 GB** | Чтобы `npm install`/`pnpm install` OpenClaw не падал OOM | zram-generator | На 4 GB RAM VPS — **swapfile, не zram**. zram сжимает в RAM, а у нас и так дефицит RAM на сборку. Swapfile = страховка от OOM, не «ускоритель». |
| Firewall | **ufw 0.36.2** | Минимум: 22/tcp с rate-limit | nftables (raw), iptables | ufw — фронтенд к nftables на 24.04, проще держать в голове. Если нужны сложные DOCKER-USER-цепочки — переход на nftables. |
| fail2ban | **1.0.2** (apt) | Бан перебора SSH | crowdsec, sshguard | fail2ban — стандарт, recidive-jail из коробки. crowdsec мощнее, но сложнее, для одного VPS overkill. |
| Auto-updates | **unattended-upgrades 2.9.1** | Только security-патчи | apt-get cron | Дефолт в Ubuntu, security-only — самая безопасная конфигурация для прода. |
| SSH-ключ | **ed25519** (32 байта) | Замена пароля | RSA-4096 (ОК), ECDSA (избегать) | ed25519 — короче, быстрее, безопаснее, поддерживается OpenSSH с 6.5 (везде). RSA-4096 валиден, но «вышел из моды». |
| Часовой пояс | **UTC** на сервере | Логи без смещений, корректные cron-сравнения | Europe/Moscow и т.д. | UTC — единственный sane выбор для прод-сервера. Локальное время — только в дашборде/UI, не в логах. |
| Locale | **en_US.UTF-8** + `C.UTF-8` дефолт | Совместимость с Node, MCP | ru_RU.UTF-8 | Node + npm + многие MCP-серверы лажают на не-UTF-8 локалях. Держим en_US.UTF-8 + LANG=C.UTF-8 в systemd-user. |
| ulimit nofile | **65535** soft / **1048576** hard | Под daemon + множество MCP-stdio | 1024 (default) | OpenClaw Gateway мультиплексирует WS + spawn-ит MCP-процессы. Дефолт 1024 закончится через 30–50 MCP. |

---

## Лайфхаки и про-приёмы

1. **`ufw limit 22/tcp` вместо `ufw allow 22/tcp`.** Команда `limit` добавляет в правило rate-limit (6 connect-попыток за 30 сек с одного IP — дальше DROP). Это сильнее снижает нагрузку чем fail2ban: до журнала вообще не доходит. Проверяется так: `sudo ufw status verbose | grep 22/tcp` — должно быть `LIMIT IN`.

2. **Включи `loginctl enable-linger clawd` СРАЗУ.** Без этого systemd-user-сервисы (а у OpenClaw daemon именно такой) умирают при `exit` из SSH. Симптом: «всё работало, потом я отключился — теперь Telegram-бот молчит». Это самая частая ошибка №1 у OpenClaw-новичков (Florian Darroman называет её «the most frequently overlooked step»). Команда: `sudo loginctl enable-linger clawd`. Проверка: `loginctl show-user clawd | grep Linger` — должно быть `Linger=yes`.

3. **`chmod 600 ~/.openclaw/openclaw.json` форсированно после `openclaw onboard`.** Onboard иногда оставляет 644. В файле — токены Telegram/Discord, OPENROUTER_API_KEY и прочая отрава. Лучше прописать в `~/.bashrc` алиас `alias claw-secure='chmod 600 ~/.openclaw/openclaw.json && chmod 700 ~/.openclaw'`.

4. **Своп-файл сразу 4 GB, а не 2 GB как пишут.** Многие гайды (включая Florian Darroman) рекомендуют 2 GB. Под OpenClaw на 4 GB-VPS этого не хватает: `pnpm install` пакетов с нативным сборкой (`@discordjs/opus`, `sharp`, `better-sqlite3` через MCP) уверенно жрёт пик 1.5–2 GB swap. **4 GB swap — золотая середина**, не съедает много диска и спасает в момент сборки.

5. **`vm.swappiness=10`, не дефолтный 60.** Для VPS с swap-файлом на одном диске — низкая swappiness снижает износ диска и латентность. `echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf && sudo sysctl --system`. Без этого Linux агрессивно свопает данные Node, и при ответе бота в Telegram появляются «лаги на ровном месте».

6. **NodeSource ставит Node от root в `/usr/bin/node` — это НОРМАЛЬНО, не используй sudo для npm.** Самая частая EACCES-ошибка с OpenClaw (Issue #23861) — люди пытаются `sudo npm i -g openclaw`, потом не могут запустить от `clawd`. Правильный путь: настроить **user-prefix** для npm: `mkdir -p ~/.npm-global && npm config set prefix ~/.npm-global && echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc && source ~/.bashrc`. И тогда `npm i -g openclaw` ставит в `/home/clawd/.npm-global/bin/`.

7. **`Port 22` оставляй, но добавь `MaxAuthTries 3` и `LoginGraceTime 20`.** «Меняйте порт SSH» — мифологический совет 2010-х. Современные ботнеты сканируют все 65535 портов за минуты. **Реально работает**: ed25519-only, fail2ban, ufw limit. Менять порт = ломать совместимость со всеми скриптами/IDE.

8. **`AllowUsers clawd` в sshd_config — вторая линия обороны.** Даже если кто-то заведёт `git`-юзера или забудешь снести `ubuntu`-юзера от провайдера, SSH пустит **только `clawd`**. Один из тех настроев, который никогда не пригодится — пока не пригодится.

9. **`fail2ban` на 24.04 = `backend = systemd`, явно.** Дефолт-debian-конфиг это уже делает, но многие копипастят гайды 2022 года с `logpath = /var/log/auth.log`, а файла такого больше нет (журнал ушёл в journald). Проверка: `sudo fail2ban-client status sshd` должен показать «Banned IP list» и что-то ловить за час. Если 0 banned за сутки на публичном VPS — конфиг сломан.

10. **`recidive`-jail = «бан на неделю за повторные баны».** Это второй уровень: первый бан 1 час, на третий бан подряд recidive прилетает с bantime 7 дней. Без recidive один и тот же ботнет долбит вас по кругу каждый час. Включается в `jail.local` отдельной секцией.

11. **`unattended-upgrades` — security-only, без `-updates`/`-backports`, и **без `Automatic-Reboot "true"`**.** Иначе сервер в 06:00 уйдёт в ребут посреди ответа в Telegram. Если хочешь авто-ребут — поставь `Automatic-Reboot-Time "04:00"` И `Unattended-Upgrade::Automatic-Reboot-WithUsers "false"` (не ребутить, если кто-то залогинен).

12. **`LimitNOFILE=1048576` в `~/.config/systemd/user.conf.d/limits.conf`.** OpenClaw spawn-ит MCP-серверы как stdio-процессы. Каждый = пара пайпов = 4 fd. Плюс WebSocket каналы (Telegram, Discord polling). На 50 MCP + 5 каналов легко уйти за дефолтный 1024. Симптом: `EMFILE: too many open files` в логах daemon, **рандомные** падения.

13. **IPv6 — отключи на ufw, если провайдер не дал /64-префикс.** На Hetzner CX22 IPv6 даётся, на DO базовом — да, на Vultr — да. Но ботнетами IPv6-сканы ещё реже бьют — оставь включённым, ufw защитит. Главное: убедись что `IPV6=yes` в `/etc/default/ufw` и правила применяются и к v6 (`sudo ufw status` покажет `(v6)` строки).

14. **`UseDNS no` в sshd_config экономит ~3 секунды на каждое подключение.** Без этого SSH делает reverse-DNS на client_ip и ждёт таймаута, если nameserver медленный. Один из тех «магических» туненгов, которые ускоряют SSH-логин в 5–10 раз.

15. **Локаль через `update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8`, не `en_US.UTF-8`.** `C.UTF-8` — встроенная, не требует `locale-gen`, поддерживает UTF-8, и не зависит от региональных пакетов. На минимальных VPS-образах `en_US.UTF-8` иногда не сгенерирована, и Node ругается warning-ом про fallback на C.

16. **Часовой пояс — UTC: `sudo timedatectl set-timezone UTC`.** Cron в Блоке 12 будет ждать UTC-выражений, а логи journald пишут в системной зоне. Если хочешь Москву — будь готов вычитать «+3» в каждом graf-ане. UTC — стандарт.

17. **Снеси cloud-init после первого буста (опционально).** На свежеинсталленном Ubuntu 24.04 cloud-init жрёт 100–200 MB RAM каждую загрузку и продолжает фоном «применять конфиги». На голом 4 GB-VPS — заметно. `sudo apt purge cloud-init` после ручной настройки.

18. **`unminimize` на минимальных образах.** Hetzner и DO часто кладут «minimized»-образ Ubuntu без man-страниц, без некоторых утилит. Перед стартом — `sudo unminimize -y`. Иначе `man fail2ban-jail` будет показывать «No manual entry», и ты будешь думать что fail2ban сломан.

---

## Готовые команды и конфиги

### 0. Создание VPS (Hetzner Cloud, рекомендация)

В web-консоли Hetzner: New Project → Add Server → Image **Ubuntu 24.04** → Type **CX22 (Intel, €4.99)** или **CPX22 (AMD, €7.99)**. SSH-ключ **добавить во время создания** (не после), это сразу прокинет ключ root. Datacenter — Falkenstein (FSN1) или Helsinki (HEL1) — близкие к РФ по latency.

### 1. Первый вход + апгрейд + базовые утилиты

```bash
ssh root@<IP>

# Обновляемся и ставим базу
apt update && apt -y full-upgrade
apt -y install curl git build-essential ufw fail2ban \
    unattended-upgrades apt-listchanges \
    htop tmux vim ca-certificates gnupg \
    sudo rsync net-tools

# Если образ minimized
[ -f /usr/local/sbin/unminimize ] && yes | unminimize
```

### 2. Создание non-root пользователя `clawd`

```bash
adduser --disabled-password --gecos "" clawd
usermod -aG sudo clawd

# Прокидываем ключ от root к clawd
mkdir -p /home/clawd/.ssh
cp /root/.ssh/authorized_keys /home/clawd/.ssh/
chown -R clawd:clawd /home/clawd/.ssh
chmod 700 /home/clawd/.ssh
chmod 600 /home/clawd/.ssh/authorized_keys

# Sudo без пароля (только для clawd)
echo "clawd ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-clawd
chmod 440 /etc/sudoers.d/90-clawd

# Lingering — чтобы systemd-user-сервисы жили после logout
loginctl enable-linger clawd
```

### 3. SSH hardening (`/etc/ssh/sshd_config.d/99-clawd.conf`)

Создаём отдельный drop-in, не правим основной файл (на апгрейде ОС перезатирается):

```bash
cat > /etc/ssh/sshd_config.d/99-clawd.conf <<'EOF'
# OpenClaw VPS hardening
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes

AllowUsers clawd

MaxAuthTries 3
MaxSessions 5
LoginGraceTime 20
ClientAliveInterval 300
ClientAliveCountMax 2

UseDNS no
PermitEmptyPasswords no
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding yes
PrintMotd no
EOF

# Проверяем синтаксис ДО рестарта (важно!)
sshd -t && systemctl restart ssh
```

> **Прежде чем закрывать SSH-сессию — открой ВТОРОЕ окно и убедись, что `ssh clawd@<IP>` работает.** Если сломал sshd_config, у тебя есть только эта одна живая сессия чтобы починить. Hetzner/DO console доступна, но это 5 минут стресса.

### 4. Swap 4 GB

```bash
# Создаём 4G swapfile (вместо популярных 2G)
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Перманентно
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Тюнинг swappiness и cache pressure
cat > /etc/sysctl.d/99-openclaw.conf <<'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
fs.file-max = 2097152
net.core.somaxconn = 4096
EOF
sysctl --system

# Проверка
free -h
swapon --show
```

### 5. Node.js 24 LTS через NodeSource

```bash
# Под root
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt install -y nodejs

# Проверка версий
node -v   # v24.x
npm -v    # v11.x

# Заходим под clawd и настраиваем npm-prefix (НЕ под root!)
su - clawd

mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
echo 'export NODE_OPTIONS="--max-old-space-size=2048"' >> ~/.bashrc
source ~/.bashrc

# Проверка
which npm
node --version
exit  # обратно в root
```

### 6. UFW (firewall)

```bash
# Настраиваем правила ДО enable
ufw default deny incoming
ufw default allow outgoing

# IPv6 — yes
sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw

# limit, не allow! (rate-limit на 22/tcp)
ufw limit 22/tcp comment 'SSH with rate-limit'

# Включаем
ufw --force enable
ufw status verbose
```

> Для дашборда (Блок 5) позже добавишь: `ufw allow from <твой_IP> to any port 18789 comment 'OpenClaw Gateway from home'` или ничего не открывай и ходи через `ssh -L 18789:127.0.0.1:18789 clawd@<IP>` (рекомендация документации OpenClaw — Gateway вообще не должен торчать наружу).

### 7. fail2ban (`/etc/fail2ban/jail.local`)

```bash
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
# Игнорим себя (добавь свой публичный IP, чтобы не забанить себя)
ignoreip = 127.0.0.1/8 ::1
backend = systemd
banaction = ufw
banaction_allports = ufw
findtime = 10m
maxretry = 5
bantime = 1h
# Каждый следующий бан длиннее (1h, 2h, 4h, ...)
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 7d

[sshd]
enabled = true
mode = aggressive
maxretry = 3
findtime = 10m
bantime = 1h

[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
findtime = 1d
maxretry = 3
bantime = 7d
EOF

systemctl enable --now fail2ban
sleep 2
fail2ban-client status
fail2ban-client status sshd
```

### 8. unattended-upgrades (security-only, без авто-ребута)

```bash
# Включаем сам сервис
dpkg-reconfigure -f noninteractive unattended-upgrades

# Прописываем — security only
cat > /etc/apt/apt.conf.d/52unattended-upgrades-openclaw <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {
    // не обновляй ядро и nodejs автоматом
    "linux-";
    "nodejs";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

# Включаем периодичность
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
EOF

# Тестовый прогон (dry run)
unattended-upgrades --dry-run --debug | tail -20
```

### 9. Локаль и часовой пояс

```bash
timedatectl set-timezone UTC
locale-gen en_US.UTF-8 || true
update-locale LANG=C.UTF-8 LC_ALL=C.UTF-8
timedatectl status
locale
```

### 10. ulimit / LimitNOFILE для systemd-user (под clawd)

```bash
su - clawd

mkdir -p ~/.config/systemd/user.conf.d
cat > ~/.config/systemd/user.conf.d/limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65535
EOF

# Также — глобально через limits.d (для login-сессий)
exit  # обратно в root

cat > /etc/security/limits.d/99-clawd.conf <<'EOF'
clawd  soft  nofile  65535
clawd  hard  nofile  1048576
clawd  soft  nproc   65535
clawd  hard  nproc   65535
EOF
```

### 11. Финальная перезагрузка (один раз)

```bash
reboot
# через 30 сек
ssh clawd@<IP>
sudo loginctl show-user clawd | grep Linger   # Linger=yes
ulimit -n                                       # 65535
free -h                                         # swap = 4G
sudo ufw status                                 # active, 22/tcp LIMIT
sudo fail2ban-client status                     # 2 jails: sshd, recidive
```

---

## Подводные камни

1. **Заблокировал себя UFW.** Ты сделал `ufw default deny incoming` и забыл `ufw allow 22/tcp` ДО `ufw enable`. Спасение: web-console провайдера (Hetzner Cloud Console, DO Recovery Console) → запускаешь `ufw disable`. Поэтому в нашей последовательности `limit 22/tcp` идёт ДО `enable`.

2. **Ребут отвалил `linger`.** Ты не сделал `loginctl enable-linger clawd`, и после ребута OpenClaw daemon не стартует «потому что некому». Симптом: `openclaw gateway status` молчит, в Telegram-боте лаг ответов. Лечение: `sudo loginctl enable-linger clawd && systemctl --user enable openclaw-gateway`.

3. **`sudo npm i -g openclaw`** даёт EACCES при попытке запустить от clawd, потому что `/usr/local/lib/node_modules/openclaw` принадлежит root, а agent работает от clawd. Лечение: `npm config set prefix ~/.npm-global` ДО первой установки.

4. **`npm install` падает с heap out of memory** даже на 4 GB. Симптом: `JavaScript heap out of memory` или Killed. Лечение: убедись что swap включён (`swapon --show`), и `export NODE_OPTIONS="--max-old-space-size=2048"`. На 2 GB-VPS — забудь, нужно 4 GB.

5. **Часовой пояс — Москва, cron сработал не туда.** В Блоке 12 расписания у тебя UTC-cron, но сервер в MSK = смещение 3 часа. Лечение: `timedatectl set-timezone UTC` сразу.

6. **fail2ban запустился, но **ничего не ловит**.** На 24.04 это значит копипастный конфиг с `logpath = /var/log/auth.log`. Лечение: `backend = systemd` явно.

7. **PATH не подхватил `~/.npm-global/bin` после `source ~/.bashrc`.** Симптом: после `npm i -g openclaw` команда `openclaw` не найдена. Лечение: вылогиниться-залогиниться (Florian Darroman: «close your SSH session and reconnect»).

8. **OpenClaw daemon стартует, но Gateway недоступен с локального ПК.** Это **by design**: Gateway по дефолту bind = loopback (127.0.0.1), не торчит наружу. Доступ — через `ssh -L 18789:127.0.0.1:18789 clawd@<IP>`, потом в браузере `http://localhost:18789`. Никогда не открывай 18789 наружу.

9. **`unattended-upgrades` ребутнулся посреди прода.** Дефолт `Automatic-Reboot "true"` без опций. Лечение — у нас выше: `"false"` либо `"WithUsers" "false"`.

10. **Swap съел диск.** Если у тебя VPS на 40 GB, 4 GB swap — это 10% диска. На 20 GB-планах (некоторые DO базовые) уже 20%. Учти при выборе тарифа: **20 GB диска — мало для OpenClaw + workspace + node_modules + swap + логи**. Минимум 40 GB.

11. **IPv6 включён, ufw v6 — нет.** Если `IPV6=yes` в `/etc/default/ufw` забыт, ботнеты ломятся через v6 в обход твоих правил. Проверка: `sudo ufw status` должен иметь строки с `(v6)`.

12. **Hetzner снёс VPS за «ssh бан».** Если у тебя на сервере уже есть кто-то с подбором пароля и ты НЕ настроил fail2ban за первые часы — Hetzner abuse-team может написать письмо. Поэтому fail2ban настраиваем в **первый час**, а не «потом».

---

## Чек-лист выполнения

- [ ] VPS создан (Ubuntu 24.04 LTS, минимум 2 vCPU/4 GB RAM/40 GB SSD)
- [ ] SSH-ключ ed25519 сгенерирован локально (`ssh-keygen -t ed25519 -C "openclaw-vps"`)
- [ ] Первый вход root@IP по ключу прошёл
- [ ] `apt full-upgrade` выполнен
- [ ] Ставлены: `curl git build-essential ufw fail2ban unattended-upgrades`
- [ ] Создан пользователь `clawd` с sudo
- [ ] SSH-ключ скопирован в `/home/clawd/.ssh/authorized_keys` (700/600)
- [ ] `loginctl enable-linger clawd` выполнен
- [ ] `/etc/ssh/sshd_config.d/99-clawd.conf` создан, `sshd -t` без ошибок
- [ ] **Проверено второе SSH-окно — `ssh clawd@<IP>` работает** ДО рестарта sshd на основной сессии
- [ ] `systemctl restart ssh` выполнен
- [ ] Swap 4 GB создан, в `/etc/fstab`, `vm.swappiness=10` применён
- [ ] Node 24 LTS установлен через NodeSource (`node -v` = v24.x)
- [ ] npm-prefix настроен в `~/.npm-global` под clawd
- [ ] `NODE_OPTIONS="--max-old-space-size=2048"` в `~/.bashrc` clawd
- [ ] UFW: default deny in, allow out, **`ufw limit 22/tcp`**, IPv6=yes, enabled
- [ ] fail2ban: `jail.local` с `backend = systemd`, sshd-jail, recidive-jail активны
- [ ] unattended-upgrades: security-only, `Automatic-Reboot "false"` (или WithUsers false)
- [ ] Часовой пояс = UTC
- [ ] Locale = `C.UTF-8`
- [ ] LimitNOFILE=1048576 в `~/.config/systemd/user.conf.d/limits.conf` под clawd
- [ ] `/etc/security/limits.d/99-clawd.conf` создан
- [ ] Ребут — сервер поднялся, `linger=yes`, `ulimit -n` = 65535, swap на месте
- [ ] (опц.) `apt purge cloud-init` если планируется долговременная работа

---

## Верификация

Команды и ожидаемый вывод:

```bash
# 1. SSH-конфиг — root заблокирован, password — нет
sudo sshd -T | grep -E "permitrootlogin|passwordauthentication|allowusers"
# permitrootlogin no
# passwordauthentication no
# allowusers clawd

# 2. UFW активен и rate-limit на 22
sudo ufw status verbose | head -15
# Status: active
# Default: deny (incoming), allow (outgoing)
# 22/tcp                     LIMIT IN    Anywhere
# 22/tcp (v6)                LIMIT IN    Anywhere (v6)

# 3. fail2ban живой и ловит
sudo fail2ban-client status
# Number of jail: 2
# Jail list:  recidive, sshd

sudo fail2ban-client status sshd
# Currently failed: N
# Currently banned: M  (на публичном IP за час обычно 5-50)

# 4. Swap — 4 GB
free -h | grep Swap
# Swap:           4.0Gi          0B       4.0Gi

cat /proc/sys/vm/swappiness
# 10

# 5. Node 24
node -v
# v24.x.x

npm -v
# 11.x.x

# 6. linger включён
loginctl show-user clawd | grep Linger
# Linger=yes

# 7. Лимиты под clawd
sudo -u clawd bash -c 'ulimit -n'
# 65535

# 8. Locale + TZ
timedatectl status | grep -i zone
# Time zone: UTC (UTC, +0000)

locale | head -3
# LANG=C.UTF-8
# LC_ALL=C.UTF-8

# 9. unattended-upgrades dry-run
sudo unattended-upgrades --dry-run --debug 2>&1 | grep -E "^(Allowed|Initial|Checking)"
# должны быть строки про -security оригины, без -updates/-backports

# 10. Готовность к Блоку 2 — установка OpenClaw тестово
sudo -iu clawd bash -c 'npm install -g openclaw@latest'
# должно отработать без EACCES, без OOM
sudo -iu clawd bash -c 'openclaw --version'
# v2026.x.x
```

Если все 10 проверок зелёные — фундамент готов, можно запускать `openclaw onboard --install-daemon` в Блоке 2.

---

## Реальная оценка времени

- **Минимум (опытный sysadmin, всё в голове, копипаст из своих gist):** 30 мин
- **Реалистично (с этим документом, читать-копипастить-проверять):** 45–55 мин
- **С косяками (заблокировал себя через UFW, ребутил, искал почему linger не работает, ловил EACCES на npm):** 90–120 мин

**Где обычно теряется время:**
- 5–10 мин — заблокировал себя SSH/UFW, восстанавливаешься через web-console
- 5–10 мин — `npm i -g openclaw` падает на EACCES, разбираешься
- 5 мин — забыл `linger`, после ребута — daemon не стартует
- 5–10 мин — locale/timezone (если выбрал не UTC, потом будешь возвращаться в Блок 12)

---

## Связи с другими блоками

- **ДО:** ничего (это первый блок).
- **ПОСЛЕ:**
  - **Блок 2 (Установка OpenClaw):** ляжет на этот фундамент — `openclaw onboard --install-daemon` создаст systemd-user-сервис, для которого критичны `linger=yes` и `LimitNOFILE` из этого блока.
  - **Блок 3 (Скиллы и MCP):** требует `LimitNOFILE` хотя бы 65k (десятки MCP-stdio-процессов).
  - **Блок 5 (Дашборд/Канвас):** будет добавлять разрешение на 18789 в UFW (или ходить через SSH-туннель — рекомендуется).
  - **Блок 9 (Каналы — Telegram, Discord):** требует исходящий доступ (allow outgoing — уже есть) и стабильный uptime (linger, swap).
  - **Блок 11 (Security audit):** будет проверять fail2ban-баны, unattended-upgrades, ed25519, AllowUsers — всё из этого блока.
  - **Блок 12 (Cron и расписания):** сильно зависит от `timedatectl=UTC` из этого блока, иначе будет смещение часов.

---

## Источники

- [OpenClaw — Install (официальная документация)](https://docs.openclaw.ai/install) — проверено 2026-04-29
- [OpenClaw — Gateway Security](https://docs.openclaw.ai/gateway/security) — проверено 2026-04-29
- [openclaw/openclaw GitHub README](https://github.com/openclaw/openclaw) — проверено 2026-04-29
- [Issue #41778 — openclaw-message OOM on 4GB servers since v2026.3.7](https://github.com/openclaw/openclaw/issues/41778) — проверено 2026-04-29
- [Issue #23861 — npm install failed for openclaw@latest (EACCES)](https://github.com/openclaw/openclaw/issues/23861) — проверено 2026-04-29
- [Issue #53547 — Bootstrap files not loaded from workspace in 2026.3.23-2](https://github.com/openclaw/openclaw/issues/53547) — проверено 2026-04-29
- [Florian Darroman — How to Install OpenClaw on a VPS (complete guide), Mar 2026](https://florian-darroman.medium.com/how-to-install-openclaw-on-a-vps-complete-guide-707343fa070c) — проверено 2026-04-29
- [Ewan Mak — Deploy OpenClaw on Ubuntu VPS, Mar 2026](https://medium.com/@tentenco/how-to-deploy-openclaw-on-an-ubuntu-vps-a-complete-beginners-guide-to-your-24-7-ai-agent-3b99866cb733) — проверено 2026-04-29
- [Contabo Blog — OpenClaw Security Guide 2026](https://contabo.com/blog/openclaw-security-guide-2026/) — проверено 2026-04-29
- [Sébastien Dubois — How to Self-Host OpenClaw Securely on a VPS](https://www.dsebastien.net/how-to-self-host-openclaw-securely-on-a-vps-a-security-first-guide/) — проверено 2026-04-29
- [RamNode — OpenClaw Series Part 2: Installation and Security Hardening](https://ramnode.com/guides/series/openclaw/installation-security) — проверено 2026-04-29
- [LinuxCapable — Install OpenClaw on Ubuntu 24.04/26.04](https://linuxcapable.com/how-to-install-openclaw-on-ubuntu-linux/) — проверено 2026-04-29
- [getopenclaw.ai — UFW Firewall Setup for OpenClaw](https://www.getopenclaw.ai/blog/openclaw-ufw-firewall-setup) — проверено 2026-04-29
- [Meta-Intelligence — OpenClaw Gateway Commands & Port 18789](https://www.meta-intelligence.tech/en/insight-openclaw-gateway-commands) — проверено 2026-04-29
- [DigitalOcean — How to Run OpenClaw](https://www.digitalocean.com/community/tutorials/how-to-run-openclaw) — проверено 2026-04-29
- [Stack Junkie — Fix 'npm install failed for openclaw@latest' Errors](https://www.stack-junkie.com/blog/fix-openclaw-installation-errors) — проверено 2026-04-29
- [Easton Dev — Common Issues During OpenClaw Installation: 7 Fixes](https://eastondev.com/blog/en/posts/ai/20260205-openclaw-troubleshooting-guide/) — проверено 2026-04-29
- [Better Stack — DigitalOcean vs. Hetzner Cloud 2026](https://betterstack.com/community/guides/web-servers/digitalocean-vs-hetzner/) — проверено 2026-04-29
- [Better Stack — Hetzner Cloud Review 2026: Pricing and Trade-offs](https://betterstack.com/community/guides/web-servers/hetzner-cloud-review/) — проверено 2026-04-29
- [Node.js Releases — официальный schedule](https://nodejs.org/en/about/previous-releases) — проверено 2026-04-29
- [pkgpulse — Node.js 22 vs 24 (2026): npm v11 is 65% Faster](https://www.pkgpulse.com/guides/nodejs-22-vs-nodejs-24-2026) — проверено 2026-04-29
- [NodeSource — Node.js 24 Becomes LTS](https://nodesource.com/blog/nodejs-24-becomes-lts) — проверено 2026-04-29
- [OneUptime — Configure fail2ban Jails for SSH on Ubuntu, 2026-03](https://oneuptime.com/blog/post/2026-03-02-how-to-configure-fail2ban-jails-for-ssh-apache-and-nginx-on-ubuntu/view) — проверено 2026-04-29
- [OneUptime — Configure unattended-upgrades for Security Patches on Ubuntu, 2026-03](https://oneuptime.com/blog/post/2026-03-02-configure-unattended-upgrades-security-patches-ubuntu/view) — проверено 2026-04-29
- [Ubuntu Server Docs — Automatic Updates](https://ubuntu.com/server/docs/how-to/software/automatic-updates/) — проверено 2026-04-29
- [DigitalOcean — Protect SSH with Fail2ban on Ubuntu](https://www.digitalocean.com/community/tutorials/how-to-protect-ssh-with-fail2ban-on-ubuntu-20-04) — проверено 2026-04-29
- [Tecmint — Install Fail2ban for SSH Security on Ubuntu 24.04](https://www.tecmint.com/install-fail2ban-ubuntu-24-04/) — проверено 2026-04-29
- [Linux Mind — Optimize Memory Usage with zram and swap, Sep 2025](https://linuxmind.dev/2025/09/02/optimize-memory-usage-with-zram-and-swap/) — проверено 2026-04-29
- [Better Stack — NVM Alternatives Guide (fnm/volta)](https://betterstack.com/community/guides/scaling-nodejs/nvm-alternatives-guide/) — проверено 2026-04-29
- [Important Bits — Node.js, "too many open files", and ulimit](https://www.imakewebsites.ca/posts/nodejs-too-many-open-files-ulimit/) — проверено 2026-04-29
- [Capodieci — OpenClaw Workspace Files Explained: SOUL/AGENTS/HEARTBEAT](https://capodieci.medium.com/ai-agents-003-openclaw-workspace-files-explained-soul-md-agents-md-heartbeat-md-and-more-5bdfbee4827a) — проверено 2026-04-29
- [LumaDock — OpenClaw Security Best Practices Guide](https://lumadock.com/tutorials/openclaw-security-best-practices-guide) — проверено 2026-04-29
- [Nebius — OpenClaw security: architecture and hardening guide](https://nebius.com/blog/posts/openclaw-security) — проверено 2026-04-29
