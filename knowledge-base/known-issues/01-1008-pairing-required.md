# 1008 pairing required — главная ловушка установки

> **Симптом**: бот в Telegram «думает» (значок печатает) но **молчит**.
> В логах: `gateway closed (1008): pairing required: device is asking for more scopes than currently approved`
> Каждый запрос генерирует **новый** requestId (`a61be81a-...`, `0702456f-...`, etc.).

---

## 🩺 Диагноз

CLI и gateway на одной машине, но **не запарены друг с другом** через scope-систему. Любой `openclaw models status`, `openclaw devices list`, `openclaw auth list` падает в 1008.

Только `openclaw channels list` работает — он читает локальный конфиг без gateway.

## 🎯 Корневая причина

Установка прошла **без полного onboarding**. На пустом VPS правильная последовательность:

```bash
npm i -g openclaw
openclaw onboard          ← интерактивный мастер. ОБЯЗАТЕЛЬНО!
openclaw doctor --deep
```

Если AI в Antigravity на этапе установки запустил `openclaw onboard --non-interactive --auth-choice skip` (или подобное) — мастер скипает critical pairing-шаги:
- Не создаётся device-pairing запись в `~/.openclaw/.openclaw/devices/paired.json`
- CLI остаётся в read-only scope `[operator.read]`
- Любой scope-upgrade требует `operator.pairing` — chicken-and-egg

Подтверждение в `openclaw.json`:
```json
"wizard": { "lastRunCommand": "doctor" }   ← должно быть "onboard"!
```

## ✅ Фикс — переустановка через ручной onboard

⛔ **НЕ пытайся approve через `openclaw devices approve --latest --token ...`** — admin token обходит auth-слой, но НЕ scope-слой. Это разные слои защиты.

⛔ **`openclaw doctor --fix` НЕ approve-ит scope upgrade** — это by-design security gate.

✅ **Единственный надёжный путь**: снести pairing-state и пройти `openclaw onboard` заново интерактивно.

```bash
# 1. Backup всего
TS=$(date +%s)
tar czf /tmp/openclaw-backup-$TS.tar.gz -C ~ .openclaw

# 2. Сохранить ключи в Notes (нужны на onboard)
cat ~/.openclaw/secrets/models.env
cat ~/.openclaw/secrets/telegram.token

# 3. Снос
systemctl --user stop openclaw
systemctl --user disable openclaw 2>/dev/null
rm -f ~/.config/systemd/user/openclaw.service
rm -rf ~/.config/systemd/user/openclaw.service.d
mv ~/.openclaw ~/.openclaw.broken-$TS
npm uninstall -g openclaw

# 4. Чистая установка
npm i -g openclaw

# 5. Интерактивный onboard (ВАЖНО: ты сам в Mac Terminal!)
openclaw onboard
```

На вопросах мастера отвечай по cheat-sheet из `workshop-1/01-prompts.md` (Часть А2). **КРИТИЧНО**:
- Authentication mode → **token** (НЕ skip!)
- Enable device-pair plugin → **yes**

## 🔍 Как проверить что фикс сработал

```bash
openclaw devices list
# Должна быть запись со scope: [operator.admin, operator.pairing, operator.read, operator.write]

openclaw models status
# 5 провайдеров с зелёной галкой

openclaw doctor --deep | tail
# 0 critical errors

cat ~/.openclaw/.openclaw/devices/paired.json | python3 -m json.tool
# Должна быть pairing-запись для CLI с полным operator.* scope
```

## 🧠 Почему это случается

OpenClaw 2026.4.x по умолчанию запускается с `--auth-choice skip` если AI вызывает `onboard --non-interactive`. Это «тихое» поведение — мастер завершается без ошибки, но pairing **не создаётся**.

В community про это известно:
- [GitHub issue (предположительно)](https://github.com/openclaw/openclaw/issues) — известная проблема
- В docs.openclaw.ai раздел "Bootstrap" — рекомендуется только интерактивный режим

## 🛡 Профилактика

В Промпте 0 (meta) явный запрет AI запускать `openclaw onboard`:
```
⛔ ТЫ НЕ ЗАПУСКАЕШЬ openclaw onboard ни в каком виде.
   Даже с --non-interactive — этот флаг скипает pairing.
   Я делаю onboard САМ в Mac Terminal.
```

Это входит в `00-meta-prompt.md` v1.5+.

## 📚 Связанные

- `02-path-non-login-shell.md` — почему `openclaw: command not found` из cron/SSH
- `03-device-pair-disabled.md` — плагин device-pair отключён в конфиге
- `04-slug-case-sensitive.md` — после фикса 1008 проверь slug модели MiniMax
