#!/bin/bash
# ============================================================================
# pull.sh — Sync обратно с VPS на локалку
# ============================================================================
# Зачем:
#   - Бот мог сам отредактировать SOUL.md/AGENTS.md (self-improvement enabled)
#   - В memory/ накопились daily logs, которые мы хотим в git
#   - state/ файлы (last_briefing.json, todo.md) полезно знать локально
#
# Делает rsync VPS:~/.openclaw/{workspace,state,logs}/ → локально.
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

echo "📥 Sync workspace с VPS..."

# Workspace (бот мог редактировать)
rsync -avz --progress \
  -e "ssh -i $SSH_KEY" \
  --exclude='.git' \
  --exclude='secrets' \
  --exclude='browser-profiles' \
  --exclude='qdrant-data' \
  "$VPS:~/.openclaw/workspace/" "workspace/"

echo ""
echo "📥 Sync memory daily logs..."
mkdir -p workspace/memory
rsync -avz --progress \
  -e "ssh -i $SSH_KEY" \
  "$VPS:~/.openclaw/workspace/memory/" "workspace/memory/" 2>/dev/null || true

echo ""
echo "📥 Sync state и logs (для дебага)..."
mkdir -p .vps-state .vps-logs
rsync -avz \
  -e "ssh -i $SSH_KEY" \
  "$VPS:~/.openclaw/state/" ".vps-state/" 2>/dev/null || true
rsync -avz \
  -e "ssh -i $SSH_KEY" \
  --include='*.jsonl' --include='*.log' --exclude='*' \
  "$VPS:~/.openclaw/logs/" ".vps-logs/" 2>/dev/null || true

echo ""
echo "✅ Pull завершён"
echo ""
echo "💡 Что делать дальше:"
echo "   1. git diff — посмотреть что бот изменил в workspace/"
echo "   2. git add + git commit, если правки полезные"
echo "   3. git checkout -- workspace/SOUL.md, если правки не понравились"
