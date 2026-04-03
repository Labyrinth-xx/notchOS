#!/bin/bash
# Build NotchConsole and package as .app bundle
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="notchOS"
APP_DIR="${PROJECT_DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"

echo "==> Building NotchConsole..."
cd "${PROJECT_DIR}"
swift build -c release 2>&1

echo "==> Creating ${APP_NAME}.app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

# Copy binary
cp "${PROJECT_DIR}/.build/release/NotchConsole" "${CONTENTS}/MacOS/NotchConsole"

# Copy Info.plist
cp "${PROJECT_DIR}/resources/Info.plist" "${CONTENTS}/Info.plist"

# Ad-hoc codesign
echo "==> Signing..."
codesign --force --deep --sign - "${APP_DIR}"

echo "==> Done! Run with: open ${APP_DIR}"
