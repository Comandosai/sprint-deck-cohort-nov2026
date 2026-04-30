# Runbook: deploy-agent

> Стандартный deploy локальных правок (`workspace/`, `config/`) на VPS.
> Время: 2-5 минут (с верификацией).
> Источник: блок-14-git-workflow.md, PRO-04-production-hardening.md.

---

## Когда использовать

- Изменил `workspace/SOUL.md`, `USER.md`, `AGENTS.md`, `TOOLS.md`, `IDENTITY.md`, `HEARTBEAT.md`, `MEMORY.md`.
- Изменил `config/openclaw.json` (но если меняется только текстовое поле — лучше `config-patch.md`, без рестарта).
- Добавил новый MCP-сервер или skill.

**Не используй** для emergency-stop (это `emergency-stop.md`) или восстановления VPS (это `disaster-recovery.md`).

---

## Шаги (5 минут)

### 1. Pre-flight

```bash
# В корне deck
git status                          # что изменилось локально
cat .env | grep -E "^[A-Z_]+=" | wc -l   # 6+ ключей должно быть заполнено
```

Если `.env` пустой — заполни перед деплоем.

### 2. Snapshot (для отката)

```bash
git add -A
git commit -m "deploy snapshot: <короткое описание изменений>"
```

Если есть удалённый репозиторий: `git push` (не обязательно, но страховка).

### 3. Сканирование на секреты (если установлен gitleaks)

```bash
gitleaks detect --no-banner --redact
```

Если найдены — **НЕ деплой**. Удали утечку, ребейс, потом снова scan.

### 4. Запуск deploy

```bash
./scripts/deploy.sh
```

Скрипт:
- Делает локальный `git commit` (snapshot).
- `rsync` `workspace/` и `config/openclaw.json` → `VPS:~/.openclaw/`.
- Перезапускает daemon: `systemctl --user restart openclaw`.
- Запускает `openclaw doctor --deep` на VPS.

### 5. Верификация

```bash
./scripts/status.sh
```

Должно показать:
- Daemon: **Active**.
- Audit: ошибок нет.
- Gateway: слушает порт 18789.
- Spending: в пределах нормы.
- Models: все 4 в `ok`.

### 6. Smoke test в Telegram

Напиши боту в Telegram: «Привет, ты живой?». Должен ответить в стиле SOUL.md. Если молчит дольше 30 секунд — `gateway-restart.md`.

---

## Откат если что-то пошло не так

```bash
# Локально
git revert HEAD --no-edit            # откат последнего deploy snapshot
./scripts/deploy.sh                   # деплой предыдущей версии
```

Если git revert не помог (что-то с самим VPS):
```bash
# На VPS
ssh clawd-vps 'cp ~/.openclaw/openclaw.json.backup-* ~/.openclaw/openclaw.json'
ssh clawd-vps 'systemctl --user restart openclaw'
```

`deploy.sh` автоматически делает backup конфига перед каждым деплоем.

---

## Что проверить перед deploy крупных изменений

- [ ] `git status` показывает то, что я ожидаю.
- [ ] `.env` не в staged-файлах.
- [ ] Локально протестировал JSON-валидность: `python3 -c "import json; json.load(open('config/openclaw.json'))"`.
- [ ] Если менял модели — проверил slug по АУДИТу (например `deepseek/deepseek-v4-flash`, не `deepseek-flash`).
- [ ] Если менял MCP — проверил pkg name по АУДИТу (НЕ `@microsoft/mcp-server-playwright` — это `@playwright/mcp`).

---

## Связанные runbooks

- `gateway-restart.md` — если daemon не поднимается.
- `config-patch.md` — hot-reload без рестарта (для мелких правок).
- `emergency-stop.md` — если что-то горит.
