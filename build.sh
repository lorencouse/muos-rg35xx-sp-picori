#!/usr/bin/env bash
# Assemble the PortMaster zip.
#
#   ./build.sh 2.0.0                                   # fetch tmc_pc + shim, build dist/2.0.0/picori.zip
#   TMC_BINARY=./tmc_pc SDL3SHIM_LIB=./libSDL3.so.0 ./build.sh 2.0.0-dev
#
# tmc_pc comes from a tagged release of the fork, the SDL3-on-SDL2 shim from
# this repo's own releases (built by .github/workflows/release.yml); both are
# pinned by tag and SHA-256. Neither binary is in git, and only files git
# tracks under port/ go into the zip.
set -euo pipefail

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: $0 <version>" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$HERE/dist"
CACHE="$HERE/.cache"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

TMC_REPO="lorencouse/tmc"
TMC_TAG_PINNED="v0.8.3-sp8"
TMC_SHA256_PINNED="b576ff723e224f87f928414c3197365364830a4d44914eba734a598fc3490877"
TMC_TAG="${TMC_TAG:-$TMC_TAG_PINNED}"
TMC_ASSET="tmc-multi-linux-arm64-${TMC_TAG}.tar.gz"
# The pinned hash belongs to the pinned tag; another tag is checked only if
# TMC_SHA256 is given with it.
if [ "$TMC_TAG" = "$TMC_TAG_PINNED" ]; then TMC_SHA256="${TMC_SHA256:-$TMC_SHA256_PINNED}"
else TMC_SHA256="${TMC_SHA256:-}"; fi

SHIM_REPO="lorencouse/muos-rg35xx-sp-picori"
# Every release of this repo carries the shim; this is the one tested on the
# device. SDL3SHIM_TAG=latest takes the newest release, unchecked and uncached.
SHIM_TAG_PINNED="v2.2.0"
SHIM_SHA256_PINNED="e910d8660da4be3ac43048e41c7be57968cd337b106536eae9aca0f849f12af4"
SHIM_TAG="${SDL3SHIM_TAG:-$SHIM_TAG_PINNED}"
if [ "$SHIM_TAG" = "$SHIM_TAG_PINNED" ]; then SHIM_SHA256="${SDL3SHIM_SHA256:-$SHIM_SHA256_PINNED}"
else SHIM_SHA256="${SDL3SHIM_SHA256:-}"; fi
SHIM_ASSET="libSDL3.so.0"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# ELF magic plus e_machine 0xb7 (EM_AARCH64), without depending on file(1).
is_aarch64() {
  [ "$(od -An -tx1 -N4 "$1" | tr -d ' \n')" = 7f454c46 ] &&
  [ "$(od -An -tx1 -j18 -N2 "$1" | tr -d ' \n')" = b700 ]
}

for j in port/port.json port/picori/config.default.json; do
  python3 -m json.tool "$HERE/$j" >/dev/null || { echo "!! $j is not valid JSON" >&2; exit 1; }
done

mkdir -p "$DIST" "$CACHE"

# tmc_pc
if [ -n "${TMC_BINARY:-}" ]; then
  cp "$TMC_BINARY" "$STAGE/tmc_pc"
else
  bin_cache="$CACHE/tmc_pc-$TMC_TAG"
  if [ ! -f "$bin_cache" ]; then
    url="https://github.com/$TMC_REPO/releases/download/$TMC_TAG/$TMC_ASSET"
    echo "==> $url"
    curl -fL --progress-bar -o "$CACHE/$TMC_ASSET" "$url"
    mkdir -p "$CACHE/x" && tar xzf "$CACHE/$TMC_ASSET" -C "$CACHE/x"
    mv "$CACHE/x/tmc_pc" "$bin_cache"
    rm -rf "$CACHE/$TMC_ASSET" "$CACHE/x"
  fi
  cp "$bin_cache" "$STAGE/tmc_pc"
fi
got="$(sha256_of "$STAGE/tmc_pc")"
# The pin belongs to the release download; a local binary is whatever it is.
if [ -z "${TMC_BINARY:-}" ] && [ -n "$TMC_SHA256" ] && [ "$got" != "$TMC_SHA256" ]; then
  echo "!! tmc_pc SHA-256 mismatch: expected $TMC_SHA256, got $got" >&2
  echo "!! if the download was cut short: rm '$bin_cache' and run again" >&2
  exit 1
fi
[ -n "${TMC_BINARY:-}" ] || [ -n "$TMC_SHA256" ] || echo "!! tmc_pc $TMC_TAG is not pinned; set TMC_SHA256 to check it" >&2
is_aarch64 "$STAGE/tmc_pc" || { echo "!! tmc_pc is not an aarch64 ELF" >&2; exit 1; }
echo "==> tmc_pc $got"

# Every "key" in the shipped config must be one this binary knows, or the
# package promises controls the game ignores (select_state_chords on sp8).
missing=""
for key in $(sed -n 's/^    "\([a-z0-9_]*\)":.*/\1/p' "$HERE/port/picori/config.default.json"); do
  grep -qa "$key" "$STAGE/tmc_pc" || missing="$missing $key"
done
if [ -n "$missing" ]; then
  echo "!! config.default.json has keys tmc_pc does not know:$missing" >&2
  exit 1
fi

# SDL3 shim
if [ -n "${SDL3SHIM_LIB:-}" ]; then
  cp -L "$SDL3SHIM_LIB" "$STAGE/$SHIM_ASSET"
else
  if [ "$SHIM_TAG" = latest ]; then
    # "latest" moves, so never cache it.
    shim_cache="$STAGE/shim-latest"
    url="https://github.com/$SHIM_REPO/releases/latest/download/$SHIM_ASSET"
  else
    shim_cache="$CACHE/$SHIM_ASSET-$SHIM_TAG"
    url="https://github.com/$SHIM_REPO/releases/download/$SHIM_TAG/$SHIM_ASSET"
  fi
  if [ ! -f "$shim_cache" ]; then
    echo "==> $url"
    curl -fL --progress-bar -o "$shim_cache" "$url"
  fi
  cp "$shim_cache" "$STAGE/$SHIM_ASSET"
  got="$(sha256_of "$STAGE/$SHIM_ASSET")"
  if [ -n "$SHIM_SHA256" ] && [ "$got" != "$SHIM_SHA256" ]; then
    echo "!! libSDL3.so.0 SHA-256 mismatch: expected $SHIM_SHA256, got $got" >&2
    echo "!! if the download was cut short: rm '$shim_cache' and run again" >&2
    exit 1
  fi
  [ -n "$SHIM_SHA256" ] || echo "!! libSDL3.so.0 $SHIM_TAG is not pinned; set SDL3SHIM_SHA256 to check it" >&2
fi
is_aarch64 "$STAGE/$SHIM_ASSET" || { echo "!! libSDL3.so.0 is not an aarch64 ELF" >&2; exit 1; }
echo "==> libSDL3.so.0 $(sha256_of "$STAGE/$SHIM_ASSET")"

# Stage the package: tracked files only, so nothing left over from a local
# run (a ROM, saves, assets/, log.txt) can ship.
git -C "$HERE" ls-files -z -- port | (cd "$HERE" && tar --null -T - -cf -) | tar -C "$STAGE" -xf - --strip-components=1
mkdir -p "$STAGE/picori/libs.aarch64"
mv "$STAGE/tmc_pc" "$STAGE/picori/tmc_pc.aarch64"
mv "$STAGE/$SHIM_ASSET" "$STAGE/picori/libs.aarch64/$SHIM_ASSET"
chmod +x "$STAGE/picori/tmc_pc.aarch64" "$STAGE/Legend of Zelda - The Minish Cap.sh"
printf '%s\n' "$VERSION" > "$STAGE/picori/version.txt"
cp "$STAGE/cover.png" "$STAGE/picori/cover.png"

for f in "Legend of Zelda - The Minish Cap.sh" picori/tmc_pc.aarch64 picori/libs.aarch64/libSDL3.so.0 \
         picori/config.default.json picori/picori.ini port.json gameinfo.xml README.md screenshot.png cover.png \
         picori/licenses/LICENSE-picori-GPL-3.0.txt picori/licenses/LICENSE-SDL3-zlib.txt; do
  [ -e "$STAGE/$f" ] || { echo "!! missing: $f" >&2; exit 1; }
done

mkdir -p "$DIST/$VERSION"
out="$DIST/$VERSION/picori.zip"
rm -f "$out"
rm -f "$STAGE/testing_thread.txt"
( cd "$STAGE" && zip -q -r -X "$out" . -x '*.DS_Store' -x '*__MACOSX/*' )
echo "==> $out ($(du -h "$out" | cut -f1), sha256 $(sha256_of "$out"))"
