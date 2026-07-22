#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$ROOT/native"
OUTPUT="$ROOT/dist/Unwind.app"
BIN_DIR="$(cd "$NATIVE" && swift build -c release --show-bin-path)"

cd "$NATIVE"
swift build -c release

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/Contents/MacOS" "$OUTPUT/Contents/Resources"
cp "$BIN_DIR/Unwind" "$OUTPUT/Contents/MacOS/Unwind"
cp "$NATIVE/Resources/Info.plist" "$OUTPUT/Contents/Info.plist"
cp "$NATIVE/Resources"/buddy-*.png "$OUTPUT/Contents/Resources/"
chmod +x "$OUTPUT/Contents/MacOS/Unwind"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$OUTPUT"
fi

echo "$OUTPUT"
