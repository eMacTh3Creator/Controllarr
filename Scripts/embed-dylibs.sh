#!/bin/sh
#
# embed-dylibs.sh
# Controllarr
#
# Copies Homebrew-installed dylibs (libtorrent-rasterbar, OpenSSL) into the
# .app bundle's Frameworks directory and rewrites all load paths so the app
# is fully self-contained and doesn't depend on /opt/homebrew at runtime.
#
# Called as an xcodebuild post-action or standalone:
#   ./scripts/embed-dylibs.sh /path/to/Controllarr.app
#

set -euo pipefail

APP="${1:?Usage: embed-dylibs.sh /path/to/Controllarr.app}"
FRAMEWORKS="$APP/Contents/Frameworks"
MACHO="$APP/Contents/MacOS/Controllarr"
BREW="/opt/homebrew"

# Source paths
SRC_LT="$BREW/opt/libtorrent-rasterbar/lib/libtorrent-rasterbar.2.0.dylib"
SRC_SSL="$BREW/opt/openssl@3/lib/libssl.3.dylib"
SRC_CRYPTO="$BREW/opt/openssl@3/lib/libcrypto.3.dylib"

# Destination filenames
NAME_LT="libtorrent-rasterbar.2.0.dylib"
NAME_SSL="libssl.3.dylib"
NAME_CRYPTO="libcrypto.3.dylib"

mkdir -p "$FRAMEWORKS"

echo "=== Embedding dylibs into $APP ==="

# --- Copy each dylib ---
for src in "$SRC_LT" "$SRC_SSL" "$SRC_CRYPTO"; do
    case "$src" in
        *libtorrent*) name="$NAME_LT" ;;
        *libssl*)     name="$NAME_SSL" ;;
        *libcrypto*)  name="$NAME_CRYPTO" ;;
    esac

    if [ ! -f "$src" ]; then
        echo "ERROR: $src not found — is Homebrew package installed?"
        exit 1
    fi

    echo "  Copy $name"
    cp -f "$src" "$FRAMEWORKS/$name"
    chmod 755 "$FRAMEWORKS/$name"

    # Rewrite the dylib's own install name to @rpath-relative
    install_name_tool -id "@rpath/$name" "$FRAMEWORKS/$name" 2>/dev/null || true
done

# --- Rewrite the main binary's references from /opt/homebrew/... to @rpath/... ---
echo "  Rewrite main binary load paths"
install_name_tool -change "$SRC_LT"     "@rpath/$NAME_LT"     "$MACHO" 2>/dev/null || true
install_name_tool -change "$SRC_SSL"    "@rpath/$NAME_SSL"    "$MACHO" 2>/dev/null || true
install_name_tool -change "$SRC_CRYPTO" "@rpath/$NAME_CRYPTO" "$MACHO" 2>/dev/null || true

# --- Fix cross-references between embedded dylibs ---
# libtorrent links to libssl and libcrypto
LT="$FRAMEWORKS/$NAME_LT"
if [ -f "$LT" ]; then
    echo "  Rewrite libtorrent cross-references"
    install_name_tool -change "$SRC_SSL"    "@rpath/$NAME_SSL"    "$LT" 2>/dev/null || true
    install_name_tool -change "$SRC_CRYPTO" "@rpath/$NAME_CRYPTO" "$LT" 2>/dev/null || true
fi

# libssl links to libcrypto
SSL="$FRAMEWORKS/$NAME_SSL"
if [ -f "$SSL" ]; then
    echo "  Rewrite libssl cross-references"
    install_name_tool -change "$SRC_CRYPTO" "@rpath/$NAME_CRYPTO" "$SSL" 2>/dev/null || true
fi

# Ensure @rpath includes ../Frameworks (xcodebuild usually sets this, but be safe)
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACHO" 2>/dev/null || true

# --- Re-sign everything (ad-hoc) ---
echo "  Re-signing"
for f in "$FRAMEWORKS"/lib*.dylib; do
    codesign --force --sign - "$f" 2>/dev/null || true
done
codesign --force --sign - "$MACHO" 2>/dev/null || true

echo "=== Done ==="

# Verify
echo ""
echo "Verification — main binary should show @rpath/ paths:"
if ! otool -L "$MACHO" | grep -E "(torrent|ssl|crypto)"; then
    echo "WARNING: could not confirm rewritten dylib paths from main binary output"
fi
