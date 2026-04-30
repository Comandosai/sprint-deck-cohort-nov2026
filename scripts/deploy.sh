#!/bin/bash
# ============================================================================
# deploy.sh — Залить локальные правки workspace + config на VPS
# ============================================================================
# Делает:
#   1. Локальный git snapshot (откат через git revert)
#   2. Опционально: gitleaks scan на секреты
#   3. Backup текущего конфига на VPS
#   4. rsync workspace/ + config/openclaw.json → VPS:~/.openclaw/
#   5. Перезапуск daemon
#   6. openclaw doctor --deep — verify
# ============================================================================

set -e

cd "$(dirname "$0")/.." || exit 1

if [ ! -f ".env" ]; then
  echo "❌ .env не найден"
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${VPS_IP:?VPS_IP не задан}"
: "${VPS_USER:=clawd}"
SSH_KEY="${HOME}/.ssh/clawd_ed25519"
VPS="${VPS_USER}@${VPS_IP}"
SSH="ssh -i $SSH_KEY"

echo "🔍 Pre-deploy проверки..."

# 1. gitleaks scan (если установлен)
if command -v gitleaks &> /dev/null; then
  echo "  → gitleaks scan..."
  if ! gitleaks detect --no-banner --redact 2>/dev/null; then
    echo "❌ Найдены секреты в коде! Исправь и попробуй снова."
    exit 1
  fi
  echo "  ✅ Секретов нет"
else
  echo "  ⚠️  gitleaks не установлен (рекомендуется: brew install gitleaks)"
fi

# 2. JSON-валидация config
if ! python3 -c "import json; json.load(open('config/openclaw.json'))" 2>/dev/null; then
  echo "❌ config/openclaw.json — невалидный JSON"
  exit 1
fi
echo "  ✅ openclaw.json валиден"

# 3. Локальный git snapshot
if [ -d ".git" ]; then
  echo "  → git snapshot..."
  git add -A 2>/dev/null || true
  git commit -m "deploy snapshot: $(date -Iseconds)" --allow-empty 2>/dev/null || true
  echo "  ✅ Snapshot создан"
fi

# 4. Backup конфига на VPS
echo ""
echo "💾 Backup текущего конфига на VPS..."
$SSH "$VPS" "test -f ~/.openclaw/openclaw.json && cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.backup-\$(date +%s) || true"

# 5. Render openclaw.json с подстановкой переменных из .env
TMP_CONFIG=$(mktemp)
trap "rm -f $TMP_CONFIG" EXIT

# Простейшая подстановка ${VAR} → значение из env
envsubst < config/openclaw.json > "$TMP_CONFIG"

# 6. Rsync workspace
echo ""
echo "📤 Заливаем workspace/ → $VPS:~/.openclaw/workspace/..."
rsync -avz --progress \
  -e "$SSH" \
  --exclude='memory/*' \
  --exclude='.gitkeep' \
  workspace/ "$VPS:~/.openclaw/workspace/"

# 7. Залить openclaw.json
echo ""
echo "📤 Заливаем openclaw.json..."
scp -i "$SSH_KEY" "$TMP_CONFIG" "$VPS:~/.openclaw/openclaw.json"

# 8. Залить systemd unit (только если в config/systemd/)
if [ -f "config/systemd/openclaw.service" ]; then
  echo ""
  echo "📤 Заливаем systemd unit..."
  $SSH "$VPS" "mkdir -p ~/.config/systemd/user/"
  scp -i "$SSH_KEY" config/systemd/openclaw.service "$VPS:~/.config/systemd/user/"
  $SSH "$VPS" "systemctl --user daemon-reload"
fi

# 9. Перезапуск daemon
echo ""
echo "♻️  Перезапускаю daemon..."
$SSH "$VPS" 'systemctl --user restart openclaw' || {
  echo "⚠️  Restart не удался — пробую start..."
  $SSH "$VPS" 'systemctl --user start openclaw'
}
sleep 5

# 10. Verify
echo ""
echo "🩺 openclaw doctor --deep:"
$SSH "$VPS" 'openclaw doctor --deep 2>&1 | tail -15' || echo "⚠️  doctor возможно не доступен в этой версии"

echo ""
echo "✅ Deploy завершён"
echo "💡 Следующий шаг: ./scripts/status.sh"
