#!/bin/bash
# ============================================================================
# connect.sh — SSH к VPS одной командой с проброской портов
# ============================================================================
# Использование: ./scripts/connect.sh
# Пробрасывает:
#   localhost:4000 → дашборд OpenClaw (Control UI)
#   localhost:6333 → Qdrant Web UI и REST API
# ============================================================================

set -e

cd "$(dirname "$0")/.." || exit 1

# Загружаем .env
if [ ! -f ".env" ]; then
  echo "❌ .env не найден. Скопируй: cp .env.example .env, потом заполни."
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

# Проверка обязательных переменных
: "${VPS_IP:?❌ VPS_IP не задан в .env}"
: "${VPS_USER:=clawd}"

# SSH ключ
SSH_KEY="${HOME}/.ssh/clawd_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  echo "❌ SSH ключ не найден: $SSH_KEY"
  echo "Сгенерируй: ssh-keygen -t ed25519 -f $SSH_KEY -C 'comandos-claw-deck'"
  echo "Залей на VPS: ssh-copy-id -i $SSH_KEY.pub $VPS_USER@$VPS_IP"
  exit 1
fi

echo "🔗 Подключаюсь к ${VPS_USER}@${VPS_IP}..."
echo "📡 Туннели:"
echo "   localhost:4000 → дашборд OpenClaw"
echo "   localhost:6333 → Qdrant"
echo ""

exec ssh -i "$SSH_KEY" \
    -L 4000:127.0.0.1:4000 \
    -L 6333:127.0.0.1:6333 \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    "${VPS_USER}@${VPS_IP}"
