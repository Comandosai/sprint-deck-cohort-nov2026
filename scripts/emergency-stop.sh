#!/bin/bash
# ============================================================================
# emergency-stop.sh — Kill switch. Останавливает daemon за 5 секунд.
# ============================================================================
# Использовать когда:
#   - Деньги утекают (alert от провайдера, неожиданный счёт)
#   - Бот в бесконечном loop
#   - Что-то непонятное и страшное
#
# После — открой checklists/emergency-stop.md и пройди все шаги.
# ============================================================================

set -e

cd "$(dirname "$0")/.." || exit 1

if [ ! -f ".env" ]; then
  echo "❌ .env не найден — но я попробую напрямую через ssh с дефолтным алиасом"
  ssh clawd-vps 'systemctl --user stop openclaw' && {
    echo "✅ DAEMON ОСТАНОВЛЕН"
    exit 0
  }
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

echo "🚨 EMERGENCY STOP"
echo "Останавливаю OpenClaw daemon на ${VPS}..."

ssh -i "$SSH_KEY" -o ConnectTimeout=10 "$VPS" 'systemctl --user stop openclaw' && {
  echo "✅ DAEMON ОСТАНОВЛЕН"
  echo ""
  echo "⏭  Следующие шаги:"
  echo "   1. Открой checklists/emergency-stop.md"
  echo "   2. Пройди шаги 2-7 (отзыв ключей, анализ, фикс, рестарт)"
  echo ""
  echo "Если уверен что причина известна и исправлена:"
  echo "   ssh ${VPS} 'systemctl --user start openclaw'"
  exit 0
} || {
  echo "❌ SSH не работает! Если деньги ещё утекают — отзови ключи у провайдеров вручную:"
  echo "   - platform.minimax.io"
  echo "   - api-docs.deepseek.com"
  echo "   - openrouter.ai"
  echo "   - console.groq.com"
  echo "   - platform.openai.com"
  exit 1
}
