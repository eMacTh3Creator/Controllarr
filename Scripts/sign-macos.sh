#!/bin/bash
set -euo pipefail

APP=${1:?Usage: sign-macos.sh /path/to/Controllarr.app signing-identity}
IDENTITY=${2:?A valid Developer ID Application identity is required}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
test -f "$APP/Contents/Info.plist"

# Sign inside out, retaining the sandbox entitlements of Sparkle's helpers.
while IFS= read -r -d '' executable; do
    if file -b "$executable" | grep -q 'Mach-O'; then
        codesign --force --sign "$IDENTITY" --timestamp --options runtime \
            --preserve-metadata=identifier,entitlements "$executable"
    fi
done < <(find "$APP/Contents" -type f -print0)
while IFS= read -r -d '' bundle; do
    codesign --force --sign "$IDENTITY" --timestamp --options runtime \
        --preserve-metadata=identifier,entitlements "$bundle"
done < <(find "$APP/Contents" -depth -type d \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' \) -print0)
codesign --force --sign "$IDENTITY" --timestamp --options runtime \
    --entitlements "$ROOT/App/Controllarr.release.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP"
