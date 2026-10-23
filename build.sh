#!/bin/bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SOURCE_DIR/dist"
APP="$OUTPUT_DIR/Codex Usage.app"
STAGING="$OUTPUT_DIR/Codex Usage.app.next"
PREVIOUS="$OUTPUT_DIR/Codex Usage.app.previous"
ARM_TRIPLE="arm64-apple-macosx13.0"
INTEL_TRIPLE="x86_64-apple-macosx13.0"
PORTABLE=0
if [[ "${1:-}" == "--portable" ]]; then PORTABLE=1; fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
trap 'rm -rf "$STAGING"' EXIT

swift build --package-path "$SOURCE_DIR" --triple "$ARM_TRIPLE" -c release --product CodexUsage
swift build --package-path "$SOURCE_DIR" --triple "$INTEL_TRIPLE" -c release --product CodexUsage
ARM_BINARY="$SOURCE_DIR/.build/arm64-apple-macosx/release/CodexUsage"
INTEL_BINARY="$SOURCE_DIR/.build/x86_64-apple-macosx/release/CodexUsage"
lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$STAGING/Contents/MacOS/CodexUsage"

RESOURCE_BUNDLE="$SOURCE_DIR/.build/arm64-apple-macosx/release/CodexUsage_CodexUsage.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "Missing Swift package resource bundle: $RESOURCE_BUNDLE" >&2
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$STAGING/Contents/Resources/CodexUsage_CodexUsage.bundle"

CODEX_COMMAND=""
CODEX_BINARY=""
if [[ "$PORTABLE" != "1" ]]; then
    CODEX_COMMAND="$(command -v codex || true)"
    CODEX_BINARY="$CODEX_COMMAND"
fi
if [[ -n "$CODEX_COMMAND" ]] && command -v node >/dev/null 2>&1; then
    RESOLVED_BINARY="$(node - "$CODEX_COMMAND" 2>/dev/null <<'NODE' || true
const fs = require('fs');
const path = require('path');
const {createRequire} = require('module');
try {
  const cli = fs.realpathSync(process.argv[2]);
  const req = createRequire(cli);
  const pkg = req.resolve(`@openai/codex-darwin-${process.arch}/package.json`);
  const triple = process.arch === 'arm64' ? 'aarch64' : 'x86_64';
  const binary = path.join(path.dirname(pkg), 'vendor', `${triple}-apple-darwin`, 'bin', 'codex');
  fs.accessSync(binary, fs.constants.X_OK);
  console.log(binary);
} catch { /* Keep the CLI entry point; app-server launch will report any failure. */ }
NODE
    )"
    if [[ -n "$RESOLVED_BINARY" ]]; then CODEX_BINARY="$RESOLVED_BINARY"; fi
fi
printf '%s\n' "$CODEX_BINARY" > "$STAGING/Contents/Resources/codex-path"

cat > "$STAGING/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexUsage</string>
<key>CFBundleIdentifier</key><string>local.codex.usage-bar</string>
<key>CFBundleName</key><string>Codex Usage</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

plutil -lint "$STAGING/Contents/Info.plist"
lipo "$STAGING/Contents/MacOS/CodexUsage" -verify_arch arm64 x86_64
codesign --force --sign - "$STAGING"
codesign --verify --deep --strict "$STAGING"

if [[ -e "$APP" ]]; then
    rm -rf "$PREVIOUS"
    mv "$APP" "$PREVIOUS"
fi
mv "$STAGING" "$APP"
trap - EXIT
printf '%s\n' "$APP"
