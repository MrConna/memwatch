#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="$ROOT_DIR/dist/MemWatch.app"
APP_DEST="/Applications/MemWatch.app"

"$ROOT_DIR/scripts/build-app.sh" >/dev/null

pkill -f '/MemWatch.app/Contents/MacOS/MemWatch' 2>/dev/null || true
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"
open "$APP_DEST"

cat <<'MESSAGE'
MemWatch installed to /Applications/MemWatch.app and started.

Look for "MEM xx%" in the menu bar.

To start MemWatch with macOS:
1. Open System Settings
2. Go to General > Login Items
3. Add /Applications/MemWatch.app
MESSAGE
