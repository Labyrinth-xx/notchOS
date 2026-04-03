#!/bin/bash
# Launch notchOS: backend + app
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${PROJECT_DIR}/notchOS.app"

# Check if app exists
if [ ! -d "$APP_DIR" ]; then
  echo "App not found. Building..."
  bash "${PROJECT_DIR}/scripts/bundle.sh"
fi

# Kill any existing instances
pkill -f "uvicorn backend.server:app.*23456" 2>/dev/null || true
pkill -f "NotchConsole" 2>/dev/null || true
sleep 0.5

# Start backend
echo "Starting backend on :23456..."
cd "${PROJECT_DIR}"
python3 -m uvicorn backend.server:app --host 127.0.0.1 --port 23456 --log-level info &
BACKEND_PID=$!

# Wait for backend to be ready
for i in {1..10}; do
  if curl -s http://127.0.0.1:23456/api/state > /dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

# Start app
echo "Starting notchOS app..."
open "${APP_DIR}"

echo "notchOS running! (backend PID: ${BACKEND_PID})"
echo "Press Ctrl+C to stop."

# Trap cleanup
trap "kill ${BACKEND_PID} 2>/dev/null; pkill -f NotchConsole 2>/dev/null; echo 'Stopped.'" EXIT

wait ${BACKEND_PID}
