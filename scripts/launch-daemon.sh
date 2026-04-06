#!/bin/bash
# notchOS background launcher for LaunchAgent (no interactive trap/wait)
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${PROJECT_DIR}/notchOS.app"

# Kill any existing instances
pkill -f "uvicorn backend.server:app.*23456" 2>/dev/null || true
pkill -f "NotchConsole" 2>/dev/null || true
sleep 0.5

# Check if app exists
if [ ! -d "$APP_DIR" ]; then
  echo "App not found. Building..."
  bash "${PROJECT_DIR}/scripts/bundle.sh"
fi

# Start backend
echo "$(date): Starting backend on :23456..."
cd "${PROJECT_DIR}"
source "${PROJECT_DIR}/.venv/bin/activate" 2>/dev/null || true
python3 -m uvicorn backend.server:app --host 127.0.0.1 --port 23456 --log-level info &

# Wait for backend to be ready
for i in {1..10}; do
  if curl -s http://127.0.0.1:23456/api/state > /dev/null 2>&1; then
    echo "$(date): Backend ready."
    break
  fi
  sleep 0.5
done

# Start app
echo "$(date): Starting notchOS app..."
open "${APP_DIR}"

echo "$(date): notchOS launched successfully."
