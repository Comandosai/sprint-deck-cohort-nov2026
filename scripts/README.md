# scripts/

Bash-скрипты для типовых операций с VPS. Все исполняемые (`chmod +x`).

---

## Скрипты

| Скрипт | Что делает | Когда |
|---|---|---|
| `connect.sh` | SSH к VPS с туннелем `:4000 → дашборд` и `:6333 → Qdrant` | каждый раз когда руками лезешь на VPS |
| `deploy.sh` | git snapshot → rsync `workspace/` + `config/openclaw.json` → VPS → restart daemon | после изменений в `workspace/` или `config/` |
| `status.sh` | Healthcheck: daemon, gateway, spending, models, RAM, диск | проверить что бот живой |
| `pull.sh` | rsync обратно с VPS (бот мог редактировать SOUL.md, накопить daily logs) | раз в день для git-снапшота |
| `emergency-stop.sh` | `systemctl --user stop openclaw` за 5 секунд | когда что-то горит |

---

## Зависимости

- `ssh`, `rsync`, `scp` (стандартные на macOS/Linux).
- `python3` для JSON-валидации в `deploy.sh`.
- `jq` (опц.) для парсинга в `status.sh` — `brew install jq`.
- `gitleaks` (опц.) для сканирования секретов — `brew install gitleaks`.
- `envsubst` (`gettext` на macOS — `brew install gettext && brew link --force gettext`).

---

## Перед первым запуском

```bash
chmod +x scripts/*.sh
cp .env.example .env
# заполни .env (минимум VPS_IP, VPS_USER, и API-ключи провайдеров)
ssh-keygen -t ed25519 -f ~/.ssh/clawd_ed25519 -C "comandos-claw-deck"
ssh-copy-id -i ~/.ssh/clawd_ed25519.pub clawd@<VPS_IP>
```

---

## Типовые сценарии

### Изменил SOUL.md → деплой
```bash
./scripts/deploy.sh
./scripts/status.sh
```

### Бот молчит → проверить и перезапустить
```bash
./scripts/status.sh                                        # видишь Daemon: Down
./scripts/connect.sh                                       # ssh
sudo systemctl --user restart openclaw                    # или ./scripts/connect.sh + restart
```

### Деньги утекают → СТОП
```bash
./scripts/emergency-stop.sh
# дальше — checklists/emergency-stop.md
```

### Раз в день — backup памяти
```bash
./scripts/pull.sh
git add -A && git commit -m "memory sync"
```

---

## Архитектура

```
[Локально]                       [VPS]
─────────                        ───────
.env (секреты)                   ~/.openclaw/
workspace/   ──── deploy.sh ──→   ├── workspace/
config/      ──── deploy.sh ──→   ├── openclaw.json
             ←──── pull.sh ─────  ├── memory/ (daily logs)
                                  ├── state/ (heartbeat, briefing)
                                  └── logs/
```

Скрипты — это «truck для грузов» между локалкой и VPS.
