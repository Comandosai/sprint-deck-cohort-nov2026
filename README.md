# Comandos Claw Deck

> Пульт управления удалённым OpenClaw-агентом на VPS.
> Это рабочее окружение, которое ты открываешь в Antigravity. AI-плагин (Claude Code или Codex) управляет ботом по SSH через скрипты из этой папки.

---

## Что это

`comandos-claw-deck/` — твоя «диспетчерская». В ней лежат:

- **`workspace/`** — личность бота (SOUL, USER, AGENTS, TOOLS и т.д.). Заливается на VPS через `scripts/deploy.sh`.
- **`config/`** — конфиги: `openclaw.json`, `docker-compose.qdrant.yml`, systemd unit.
- **`checklists/`** — оперативные runbooks: «что делать если упало».
- **`scripts/`** — bash для типовых операций (SSH, deploy, healthcheck, emergency stop).
- **`docs/`** — справки, к которым обращаешься на лету (команды бота, troubleshooting, glossary).
- **`skills/`** — место для кастомных OpenClaw skills.

Сам бот живёт **на VPS**, не на твоём компьютере. Эта папка — пульт, не сервер.

---

## Как открыть

```bash
git clone <твой-репо> comandos-claw-deck
cd comandos-claw-deck
cp .env.example .env       # заполни ключи
chmod +x scripts/*.sh      # сделать скрипты исполняемыми
```

Открой папку в Antigravity. AI-плагин автоматически прочитает `AGENTS.md` (корневой) и поймёт, как управлять ботом.

---

## Первый запуск

1. Заполни `.env` (4 обязательных ключа: MiniMax, DeepSeek, OpenRouter, Groq + Telegram).
2. Создай SSH-ключ к VPS: `ssh-keygen -t ed25519 -f ~/.ssh/clawd_ed25519 -C "comandos-claw"`
3. Добавь публичный ключ на VPS: `ssh-copy-id -i ~/.ssh/clawd_ed25519.pub clawd@<VPS_IP>`
4. Подключись: `./scripts/connect.sh`
5. Заполни плейсхолдеры `{{...}}` в `workspace/SOUL.md`, `workspace/USER.md`.
6. Деплой: `./scripts/deploy.sh`
7. Healthcheck: `./scripts/status.sh`

---

## Главные правила

- **`.env` НЕ коммитить.** Уже в `.gitignore`.
- **Перед `deploy.sh`** — `git commit`. Откат через `git revert`.
- **Не редактируй конфиги на VPS вручную.** Меняй локально, потом `deploy.sh`.
- **Если что-то горит** — открой `checklists/emergency-stop.md`.

---

## Архитектура одной картинкой

```
[Telegram] ←→ [VPS: OpenClaw daemon] ←→ [LLM-провайдеры]
                    ↑
                    │ SSH (через ./scripts/)
                    │
[Этот deck в Antigravity + AI-плагин]
```

Бот в Telegram отвечает с VPS. Ты редактируешь его личность здесь и накатываешь через deploy.

---

## Куда смотреть в первую очередь

| Нужно | Файл |
|---|---|
| Что говорит бот в ответ | `workspace/SOUL.md` |
| Кого знает бот | `workspace/USER.md` |
| Конфиг моделей и спендинга | `config/openclaw.json` |
| Список команд бота | `docs/commands.md` |
| Бот молчит / упал | `docs/troubleshooting.md` |
| Деньги утекают (СРОЧНО) | `checklists/emergency-stop.md` |
| VPS умер | `checklists/disaster-recovery.md` |
| Слова непонятны | `docs/glossary.md` |

---

## Ссылки

- OpenClaw сайт: https://openclaw.ai
- Документация: https://docs.openclaw.ai
- Репозиторий: https://github.com/openclaw/openclaw

---

**Версия deck:** 1.0.0
**Подготовлено:** Дмитрий Попов (@ai_comandos)
