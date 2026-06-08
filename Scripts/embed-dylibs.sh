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
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Source paths.
#
# Prefer the project's patched libtorrent (vendor/libtorrent-patched) when it
# has been built — it carries a defensive re-entrancy hardening of
# resolver::on_lookup for large-library stability. Fall back to the stock
# Homebrew dylib otherwise. Build the patched copy with
# scripts/build-patched-libtorrent.sh. Both are libtorrent 2.0.12 and
# ABI-identical, so the app can link the Homebrew copy and embed either.
SRC_LT_VENDOR="$ROOT/vendor/libtorrent-patched/lib/libtorrent-rasterbar.2.0.dylib"
SRC_LT_BREW="$BREW/opt/libtorrent-rasterbar/lib/libtorrent-rasterbar.2.0.dylib"
if [ -f "$SRC_LT_VENDOR" ]; then
    SRC_LT="$SRC_LT_VENDOR"
    echo "  Using patched libtorrent: $SRC_LT_VENDOR"
else
    SRC_LT="$SRC_LT_BREW"
    echo "  Using Homebrew libtorrent (patched copy not built): $SRC_LT_BREW"
fi
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

# --- Rewrite EVERY /opt/homebrew dependency to @rpath/<basename> ---
#
# Read the ACTUAL install names out of each Mach-O with otool rather than
# assuming hardcoded source paths. Homebrew bakes a mix of layouts —
# `opt/<formula>/lib/...`, versioned `Cellar/<formula>/<ver>/lib/...` — and
# the binary's libtorrent reference comes from whatever it linked against, not
# from the file we copied. Assuming a single "from" path (the old approach)
# silently no-ops when it doesn't match, which is exactly how 2.1.11/2.1.12
# shipped with absolute /opt/homebrew paths that crash at launch on machines
# without Homebrew. Rewriting whatever otool reports is robust to all of it.
rewrite_brew_refs() {
    macho="$1"
    [ -f "$macho" ] || return 0
    otool -L "$macho" | awk 'NR>1 {print $1}' | while IFS= read -r ref; do
        case "$ref" in
            /opt/homebrew/*)
                base=$(basename "$ref")
                echo "    $(basename "$macho"): $ref -> @rpath/$base"
                install_name_tool -change "$ref" "@rpath/$base" "$macho" 2>/dev/null || true
                ;;
        esac
    done
}

echo "  Rewriting Homebrew references to @rpath"
rewrite_brew_refs "$MACHO"
for f in "$FRAMEWORKS"/lib*.dylib; do
    rewrite_brew_refs "$f"
done

# Ensure @rpath includes ../Frameworks (xcodebuild usually sets this, but be safe)
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACHO" 2>/dev/null || true

# --- Re-sign everything (ad-hoc) ---
echo "  Re-signing"
for f in "$FRAMEWORKS"/lib*.dylib; do
    codesign --force --sign - "$f" 2>/dev/null || true
done
codesign --force --sign - "$MACHO" 2>/dev/null || true

# --- Hard self-containment gate ---
# Fail the build if ANY Mach-O in the bundle still references /opt/homebrew.
# Without this, a non-self-contained bundle ships and crashes at launch on
# any machine that lacks the exact Homebrew libraries (see 2.1.11/2.1.12).
echo "  Verifying self-containment"
leftover=0
for f in "$MACHO" "$FRAMEWORKS"/lib*.dylib; do
    [ -f "$f" ] || continue
    if otool -L "$f" | awk 'NR>1 {print $1}' | grep -q "^/opt/homebrew"; then
        echo "ERROR: $(basename "$f") still references /opt/homebrew:"
        otool -L "$f" | awk 'NR>1 {print $1}' | grep "^/opt/homebrew" | sed 's/^/      /'
        leftover=1
    fi
done
if [ "$leftover" -ne 0 ]; then
    echo "ERROR: bundle is NOT self-contained — refusing to produce a launch-crashing app."
    exit 1
fi

echo "=== Done — bundle is self-contained (no /opt/homebrew references) ==="
