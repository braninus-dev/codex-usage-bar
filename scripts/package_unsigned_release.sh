#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.6.2"
APP_NAME="Codex Usage"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/dist/Codex-Usage-Bar-macOS-universal-v$VERSION-unsigned.zip"

"$ROOT_DIR/build.sh" --portable
lipo -archs "$APP_PATH/Contents/MacOS/CodexUsage" | grep -q 'x86_64 arm64'
codesign --verify --deep --strict "$APP_PATH"
grep -qx '' "$APP_PATH/Contents/Resources/codex-path"

rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
(cd "$(dirname "$ZIP_PATH")" && shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$ZIP_PATH").sha256")
printf 'Created %s\n' "$ZIP_PATH"
cat "$ZIP_PATH.sha256"
