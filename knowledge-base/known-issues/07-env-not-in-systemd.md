# Env-переменные с ключами не пробрасываются в systemd

> **Симптом**: ключи лежат в `~/.openclaw/secrets/models.env`, но `openclaw models status` показывает `MINIMAX_API_KEY: not set`. Daemon не видит env.

---

## 🩺 Диагноз

В systemd-user сервисе env пробрасывается **только** через директивы `Environment=` или `EnvironmentFile=`. Просто положить файл `.env` в `~/` — daemon его НЕ прочитает.

В правильно сгенерированном через `openclaw onboard` unit'е должно быть:

```ini
# ~/.config/systemd/user/openclaw.service
[Service]
ExecStart=/home/clawd/.npm-global/bin/openclaw gateway run \
  --bind loopback --port 18789 --auth token \
  --token ${OPENCLAW_GATEWAY_TOKEN} \
  --allow-unconfigured

EnvironmentFile=%h/.openclaw/secrets/gateway.env    ← OPENCLAW_GATEWAY_TOKEN
EnvironmentFile=%h/.openclaw/secrets/models.env     ← MINIMAX_API_KEY и т.д.
```

`%h` = `$HOME` пользователя (clawd) → `/home/clawd/.openclaw/secrets/...`

## 🔍 Как проверить

```bash
# Что реально видит daemon
systemctl --user show openclaw | grep -E "EnvironmentFile|Environment="

# Что в unit-файле
cat ~/.config/systemd/user/openclaw.service

# Что в секретах
ls -la ~/.openclaw/secrets/
cat ~/.openclaw/secrets/models.env  # должны быть VAR=value
```

## ✅ Фикс

### Вариант A: переустановить через onboard
`openclaw onboard` сам генерирует правильный unit с `EnvironmentFile=`.

### Вариант B: добавить вручную

Если unit уже есть, но без `EnvironmentFile=`:

```bash
# Создать override
mkdir -p ~/.config/systemd/user/openclaw.service.d
cat > ~/.config/systemd/user/openclaw.service.d/env.conf <<'EOF'
[Service]
EnvironmentFile=%h/.openclaw/secrets/gateway.env
EnvironmentFile=%h/.openclaw/secrets/models.env
EOF

# Перезагрузить unit
systemctl --user daemon-reload
systemctl --user restart openclaw
sleep 5

# Проверить
systemctl --user show openclaw | grep EnvironmentFile
```

Должно показать обе строчки.

### Вариант C: env прямо в unit

Если файлы секретов не нужны:

```bash
mkdir -p ~/.config/systemd/user/openclaw.service.d
cat > ~/.config/systemd/user/openclaw.service.d/env.conf <<EOF
[Service]
Environment="OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 24)"
Environment="MINIMAX_API_KEY=sk-..."
Environment="DEEPSEEK_API_KEY=sk-..."
Environment="OPENROUTER_API_KEY=sk-or-..."
Environment="GROQ_API_KEY=gsk_..."
Environment="OPENAI_API_KEY=sk-..."
EOF
chmod 600 ~/.config/systemd/user/openclaw.service.d/env.conf  # секреты!

systemctl --user daemon-reload && systemctl --user restart openclaw
```

⚠️ **chmod 600** обязательно — иначе ключи видны через `cat /proc/*/environ`.

## 🐛 Когда это случается

1. **AI делал systemd unit вручную** через `cat > .../openclaw.service` без `EnvironmentFile=`
2. **Ключи в `~/.env`** а не в `~/.openclaw/secrets/`
3. **systemctl --system** (system-wide) вместо `--user` — другой scope env
4. **`systemctl --user import-environment`** не вызывался

## 🛡 Профилактика

В Промпте 5 v1.5+ явный запрет:
```
⛔ ЗАПРЕЩЕНО: НЕ ЗАПУСКАЙ openclaw onboard! ...
   onboard сам сгенерирует systemd unit с правильными EnvironmentFile=
```

То есть AI **не пишет unit руками** — он только вызывает `npm i -g openclaw`. Unit генерится через `openclaw onboard` автоматически с правильными директивами.

## 📚 Связанные

- `01-1008-pairing-required.md` — главная боль, побочный эффект кривого unit
- `02-path-non-login-shell.md` — PATH в unit (тоже через Environment=)
