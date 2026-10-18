#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-bar-verify.XXXXXX")"
trap 'rm -rf "$VERIFY_TEMP_DIR"' EXIT

swift run --package-path "$SOURCE_DIR" UsageCoreChecks
python3 "$SOURCE_DIR/scripts/verify_quote_library.py"
swift build --package-path "$SOURCE_DIR" --triple arm64-apple-macosx13.0 -c release --product CodexUsage
swift build --package-path "$SOURCE_DIR" --triple x86_64-apple-macosx13.0 -c release --product CodexUsage
test -f "$SOURCE_DIR/.build/arm64-apple-macosx/release/CodexUsage_CodexUsage.bundle/quotes.json"
test -f "$SOURCE_DIR/.build/x86_64-apple-macosx/release/CodexUsage_CodexUsage.bundle/quotes.json"
lipo -create \
    "$SOURCE_DIR/.build/arm64-apple-macosx/release/CodexUsage" \
    "$SOURCE_DIR/.build/x86_64-apple-macosx/release/CodexUsage" \
    -output "$VERIFY_TEMP_DIR/CodexUsage-universal"
lipo "$VERIFY_TEMP_DIR/CodexUsage-universal" -verify_arch arm64 x86_64
QUOTE_LAYOUT_REPORT="$VERIFY_TEMP_DIR/quote-layout-measurements.csv"
case "$(uname -m)" in
    arm64) NATIVE_EXECUTABLE="$SOURCE_DIR/.build/arm64-apple-macosx/release/CodexUsage" ;;
    x86_64) NATIVE_EXECUTABLE="$SOURCE_DIR/.build/x86_64-apple-macosx/release/CodexUsage" ;;
    *) echo "Unsupported native architecture for AppKit quote measurement: $(uname -m)" >&2; exit 1 ;;
esac
"$NATIVE_EXECUTABLE" --measure-quotes "$QUOTE_LAYOUT_REPORT"
QUOTE_LAYOUT_LINES="$(wc -l < "$QUOTE_LAYOUT_REPORT" | tr -d '[:space:]')"
test "$QUOTE_LAYOUT_LINES" -eq 199
echo "198 native quote and attribution layouts measured: passed"
