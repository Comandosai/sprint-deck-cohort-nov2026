# TOOLS.md — Локальные особенности инфраструктуры

> Файл на VPS: `~/.openclaw/workspace/TOOLS.md`. Грузится в main + sub-agent сессии.
> Skills определяют **как** инструменты работают. Этот файл — **твоя конкретика** (хосты, голоса, IDs).
> Источник: блок-07-tools.md, блок-09-mcp-серверы.md.

---

## SSH (алиасы из ~/.ssh/config на VPS, если настроены)

- `{{SSH_ALIAS_1}}` → `{{SSH_HOST_1}}` — `{{SSH_DESC_1}}`
- `{{SSH_ALIAS_2}}` → `{{SSH_HOST_2}}` — `{{SSH_DESC_2}}`

<!-- Образец:
- `vps-main` → продакшн VPS, Hetzner CX22, Ubuntu 24.04 — где живу я (бот)
- `nas` → Synology DS923+ дома, бэкапы
-->

Используй `ssh <alias> "команда"`. Без `-p` и `user@`.

---

## Telegram

- **Bot token:** в `~/.openclaw/secrets/telegram.token` (не читать наружу).
- **Owner user ID:** см. `${TELEGRAM_USER_ID}` в env.
- **dmPolicy:** `allowlist` — DM принимаются только от `allowFrom`.
- **Группы:** настраиваются по `chatId` и `topicId` в `openclaw.json` → `channels.telegram.groups`.

Никогда не отправляй сообщения в группы / неизвестные DM без явного указания.

---

## Voice (Whisper транскрипция + TTS)

- **Транскрипция (вход):** Whisper Large v3 Turbo через Groq (бесплатно).
  - Язык: `ru` по умолчанию.
  - Initial prompt: `OpenClaw, OpenRouter, MiniMax, DeepSeek, Telegram` — улучшает распознавание имён.
- **TTS (выход):** OpenAI `tts-1` (НЕ `tts-1-hd` — в 2x дороже).
  - Голос: `alloy` (нейтральный, поддерживает русский).
  - Альтернатива: ElevenLabs `{{ELEVENLABS_VOICE_ID}}` для лучшего качества.
- **Voice replies:** включены автоматически (`voiceReplies: "auto"`) — если входящее голосовое, ответ тоже голосом, но только короткий (< 200 символов). Длинные ответы — текстом.

---

## Image generation

- **Default:** `google/gemini-2.5-flash-image` через OpenRouter — баланс цены и качества.
- **Fast/cheap:** `black-forest-labs/flux-schnell` через OpenRouter (в ~13x дешевле).
- Размер дефолтный: `1024x1024`.

Команда: `/image <prompt>` или просто «нарисуй ...» в чате.

---

## Browser (Playwright headless)

- Headless: всегда (на VPS нет display).
- Args обязательно: `--no-sandbox`, `--disable-dev-shm-usage`, `--disable-blink-features=AutomationControlled`.
- User data dir: `~/.openclaw/browser-profiles/main` — здесь живут cookies.
- SSRF защита включена (`dangerouslyAllowPrivateNetwork: false`).

Не пытайся обходить CAPTCHA. Где есть API (Twitter/LinkedIn/VK) — используй API, не браузер.

---

## MCP-серверы

Конфигурируются в `openclaw.json` → `mcp.servers`. Подтверждённые рабочие пакеты (см. блок-09 + АУДИТ):

| Server | Пакет | Зачем |
|---|---|---|
| **Playwright (web automation)** | `@playwright/mcp` (НЕ `@microsoft/mcp-server-playwright` — такого нет!) | управление браузером сверх native browser tool |
| **Tavily search** | `tavily-mcp` (через uvx) или `@mcptools/mcp-tavily` | продвинутый AI-поиск |
| **Notion** | `@notionhq/notion-mcp-server` (официальный) | работа с базами данных и страницами |
| **GitHub** | managed `https://api.githubcopilot.com/mcp/` или Docker `ghcr.io/github/github-mcp-server` | (НЕ `@modelcontextprotocol/server-github` — deprecated) |
| **Filesystem** | `@modelcontextprotocol/server-filesystem` | расширенный доступ к файлам |

Когда нужен новый MCP — спроси меня, не ставь самостоятельно.

---

## Vector memory (Qdrant + Mem0)

- **Qdrant:** Docker-контейнер, порт `6333` (REST), `6334` (gRPC). Persistent volume на 4 GB.
- **Mem0:** через npm-пакет `@mem0/openclaw-mem0` v1.0.10+ (см. блок-15).
- **8 memory tools** доступны: `memory_search`, `memory_add`, `memory_get`, `memory_list`, `memory_update`, `memory_delete`, `memory_event_list`, `memory_event_status`.

Для долгосрочных фактов используй `memory_add`, не `MEMORY.md` (тот для деклараций, а не для роста знания).

---

## Logging и debug

- Daemon logs: `journalctl --user -u openclaw -f` (на VPS).
- Trajectory bundles (для дебага): `OPENCLAW_TRAJECTORY=/tmp/traces` env var. Slash-команда `/trajectory bug-name` экспортирует bundle.
- Heartbeat/cron логи: `journalctl --user -u openclaw -g 'cron|heartbeat'`.

---

## Команды install/system (defaults)

- **Linux package manager:** `apt` (Ubuntu 24.04). Установка пакетов **только с подтверждением**.
- **Node:** Node.js 22 LTS установлен через nodesource.
- **Python:** `python3.12`, `uv` для venv (быстрее чем pip).
- **GitHub CLI:** `gh` доступен — используй `gh pr ...`, `gh issue ...` вместо чистого git.

---

## Что НЕ используем

- AWS — VPS у `{{HOSTING_PROVIDER}}` (Hetzner / Beget / DO).
- Windows / WSL — VPS на Linux.
- snap-версия Chromium — конфликт с AppArmor (см. `docs/troubleshooting.md`).

---

**Skills общие. Эти настройки — мои. Когда меняется инфраструктура (новый VPS, новый голос, новый MCP) — обновляй файл и `git commit`.**
