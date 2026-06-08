#!/bin/sh
#
# build-patched-libtorrent.sh
# Controllarr
#
# Builds a patched copy of libtorrent-rasterbar 2.0.12 that fixes a
# use-after-free in libtorrent::aux::resolver::on_lookup (a crash observed on
# large 700+ torrent libraries under heavy DNS/tracker churn). The patch makes
# on_lookup re-entrancy-safe by extracting and erasing the pending callbacks
# from m_callbacks BEFORE invoking any of them, and by copying the resolved
# address list out of the cache before the callback loop. See
# patches/libtorrent-2.0.12-resolver-reentrancy.patch.
#
# The result is installed into vendor/libtorrent-patched/, which
# scripts/embed-dylibs.sh prefers over the stock Homebrew dylib when present.
# The shipped .app therefore embeds the patched library; the app still links
# against the ABI-identical Homebrew copy at build time.
#
# Requirements (Apple Silicon / Homebrew):
#   brew install cmake boost openssl@3 git
#
# Usage:
#   ./scripts/build-patched-libtorrent.sh
#
# Idempotent: re-running rebuilds from a clean checkout.

set -eu

LT_VERSION="2.0.12"
LT_TAG="v${LT_VERSION}"
DYLIB_NAME="libtorrent-rasterbar.2.0.dylib"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/patches/libtorrent-${LT_VERSION}-resolver-reentrancy.patch"
VENDOR="$ROOT/vendor/libtorrent-patched"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/controllarr-libtorrent.XXXXXX")"
BREW="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [ ! -f "$PATCH" ]; then
    echo "ERROR: patch not found: $PATCH" >&2
    exit 1
fi

echo "=== Cloning libtorrent ${LT_TAG} ==="
git clone --depth 1 --branch "$LT_TAG" --recurse-submodules --shallow-submodules \
    https://github.com/arvidn/libtorrent.git "$WORK/src"

echo "=== Applying resolver re-entrancy patch ==="
git -C "$WORK/src" apply --verbose "$PATCH"

echo "=== Configuring (CMake, shared, Release, arm64) ==="
cmake -B "$WORK/build" -S "$WORK/src" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -Dencryption=ON \
    -DCMAKE_CXX_STANDARD=17 \
    -DOPENSSL_ROOT_DIR="$BREW/opt/openssl@3" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DCMAKE_INSTALL_PREFIX="$VENDOR"

echo "=== Building ==="
cmake --build "$WORK/build" --target torrent-rasterbar -j"$(sysctl -n hw.ncpu)"

echo "=== Installing into $VENDOR ==="
rm -rf "$VENDOR"
cmake --install "$WORK/build"

# The install name must match what the app/embed script expects.
PATCHED="$VENDOR/lib/$DYLIB_NAME"
if [ ! -f "$PATCHED" ]; then
    # Some generators install the fully-versioned file plus a symlink; resolve it.
    PATCHED="$(/usr/bin/find "$VENDOR/lib" -name 'libtorrent-rasterbar.2.0*.dylib' -type f | head -1)"
fi
install_name_tool -id "@rpath/$DYLIB_NAME" "$PATCHED" 2>/dev/null || true

echo ""
echo "=== Done ==="
echo "Patched dylib: $PATCHED"
echo "embed-dylibs.sh will prefer this over the Homebrew copy on the next app build."
