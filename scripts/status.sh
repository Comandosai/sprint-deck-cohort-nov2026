#!/bin/bash
# ============================================================================
# status.sh — Healthcheck OpenClaw на VPS
# ============================================================================
# Проверяет:
#   - daemon (systemctl)
#   - openclaw doctor
#   - gateway listen (порт 18789)
#   - spending today
#   - models test (4 провайдера)
#   - RAM, диск
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

echo "🔍 OpenClaw Healthcheck — $(date)"
echo "===================================="
echo ""

echo "📦 Daemon:"
if $SSH "$VPS" 'systemctl --user is-active openclaw' 2>/dev/null | grep -q active; then
  echo "  ✅ Active"
else
  echo "  ❌ Down"
  $SSH "$VPS" 'systemctl --user status openclaw --no-pager 2>&1 | head -5'
fi

echo ""
echo "🩺 openclaw doctor:"
$SSH "$VPS" 'openclaw doctor --deep 2>&1 | tail -10' || echo "  ⚠️  doctor недоступен"

echo ""
echo "🌐 Gateway (порт 18789):"
if $SSH "$VPS" 'ss -tlnp 2>/dev/null | grep -q 18789'; then
  echo "  ✅ Listening on 127.0.0.1:18789"
else
  echo "  ❌ Не слушает"
fi

echo ""
echo "💰 Spending today:"
SPEND=$($SSH "$VPS" 'openclaw spend --since="today" --json 2>/dev/null | jq -r ".total // 0"' 2>/dev/null || echo "?")
echo "  💵 \$${SPEND} USD"

echo ""
echo "🤖 Models test:"
$SSH "$VPS" 'openclaw models test --json 2>/dev/null | jq -r ".[] | \"  \(.name): \(.status)\""' 2>/dev/null || echo "  ⚠️  models test недоступен"

echo ""
echo "📊 Memory:"
$SSH "$VPS" 'free -h | grep Mem | awk "{print \"  RAM: \" \$3 \" / \" \$2 \" used\"}"'

echo ""
echo "💾 Disk:"
$SSH "$VPS" 'df -h / | tail -1 | awk "{print \"  Disk: \" \$3 \" / \" \$2 \" (\" \$5 \" used)\"}"'

echo ""
echo "🔥 Top OpenClaw processes:"
$SSH "$VPS" 'ps aux | grep -i openclaw | grep -v grep | head -3 | awk "{printf \"  PID %s: %s%% CPU, %s%% RAM — %s\\n\", \$2, \$3, \$4, \$11}"'

echo ""
echo "===================================="
echo "Done."
