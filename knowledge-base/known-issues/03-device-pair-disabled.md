# Plugin device-pair выключен → CLI не запаривается

> **Симптом**: после `openclaw onboard` файл `~/.openclaw/.openclaw/devices/paired.json` пустой или отсутствует. `openclaw devices list` показывает `No device pairing entries`. Любой scope-запрос → 1008.

---

## 🩺 Диагноз

В `~/.openclaw/openclaw.json` есть секция `plugins`:

```json
{
  "plugins": {
    "allow": ["telegram", "minimax", "deepseek", "openrouter", "groq"],
    "entries": {
      "device-pair": {
        "enabled": false           ← ВОТ ЗДЕСЬ ПРОБЛЕМА!
      }
    }
  }
}
```

Без `device-pair` плагин:
- onboard НЕ создаёт записей в `paired.json`
- gateway не может выдать scope-upgrade для CLI
- любая команда требующая scope (models status, auth list) → 1008

## 🎯 Откуда берётся выключенный плагин

В нашей боли мы видели `device-pair: enabled: false` в `openclaw.json` после того как AI **ручно лепил конфиг через jq/sed** на Промпте 6 (старая версия). AI считал плагин «опасным» (он действительно требует токен) и отключал.

В правильной установке через `openclaw onboard` плагин **включается автоматически** на этапе bootstrap.

## ✅ Фикс — включить плагин и запустить onboard

### Вариант A: лучший — переустановить через onboard

См. `01-1008-pairing-required.md` — снос `~/.openclaw` + `openclaw onboard` интерактивно.

### Вариант B: правка JSON + рестарт + onboard повторно

```bash
# Backup
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.before-fix

# Включить плагин в конфиге
python3 <<'EOF'
import json
p = '/home/clawd/.openclaw/openclaw.json'
c = json.load(open(p))

# В allow добавить device-pair если нет
if 'device-pair' not in c.get('plugins', {}).get('allow', []):
    c['plugins']['allow'].append('device-pair')

# В entries.device-pair поставить enabled: true
if 'entries' not in c['plugins']:
    c['plugins']['entries'] = {}
if 'device-pair' not in c['plugins']['entries']:
    c['plugins']['entries']['device-pair'] = {}
c['plugins']['entries']['device-pair']['enabled'] = True

json.dump(c, open(p, 'w'), indent=2)
print('✓ device-pair включён в plugins.allow и plugins.entries')
EOF

# Перезапустить daemon чтобы плагин подхватился
systemctl --user restart openclaw
sleep 5

# Запустить onboard повторно (только в интерактивном режиме!)
openclaw onboard
# На вопрос "Reuse existing config?" → yes
# На "Enable device-pair?" → yes
# Остальное по cheat-sheet из 01-prompts.md
```

После этого проверь:
```bash
openclaw devices list
# Должна быть запись с operator.* scope
```

## 🔍 Как проверить ДО запуска onboard

```bash
# Проверка plugins.allow
python3 -c "import json; c=json.load(open('/home/clawd/.openclaw/openclaw.json')); print(c.get('plugins',{}).get('allow', []))"
# Должно содержать 'device-pair'

# Проверка plugins.entries.device-pair.enabled
python3 -c "import json; c=json.load(open('/home/clawd/.openclaw/openclaw.json')); print(c.get('plugins',{}).get('entries',{}).get('device-pair',{}))"
# Должно быть {'enabled': True} (или просто отсутствовать — это тоже ок, дефолт true)
```

## 🛡 Профилактика

В Промпте 0 (meta) v1.5+ явный запрет:
```
ЗАПРЕЩЕНО ПО УМОЛЧАНИЮ (только с моего «да»):
- ❌ Отключение плагина device-pair (это причина 1008 в 90% случаев)
```

И в Промпте 5 явный отказ от ручной правки конфига:
```
⛔ ЗАПРЕЩЕНО: НЕ ЗАПУСКАЙ openclaw onboard! Я делаю onboard САМ в Mac Terminal.
```

(потому что когда AI лепит конфиг руками — он отключает то что не понимает)

## 🧠 Почему это «фича» а не баг

OpenClaw 2026.4.x защищает scope-upgrade операции через систему devices. Без `device-pair` плагина это невозможно. Это правильное поведение — но плохо документированное.

В docs.openclaw.ai раздел "Plugins" говорит «device-pair требуется для multi-device deployment». Но не сказано что **без него scope-система ломается** даже на single-device installation.

## 📚 Связанные

- `01-1008-pairing-required.md` — главная ловушка
- `08-onboard-skip-bootstrap.md` — почему onboard через AI пропускает device-pair
