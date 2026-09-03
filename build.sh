#!/usr/bin/env bash
# Assemble the distributable PortMaster zip.
#
#   ./build.sh 1.0.0                  # fetch the pinned binary, build dist/picori-1.0.0.zip
#   TMC_BINARY=/path/to/tmc_pc ./build.sh 1.0.0   # use a local build instead
#
# The 59 MB tmc_pc binary is deliberately NOT in git. It is fetched from the
# tagged release on the fork and checked against the SHA-256 below, so a build
# is reproducible without carrying a blob in history.
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: $0 <version>   (e.g. $0 1.0.0)" >&2
  exit 2
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$HERE/dist"
CACHE="$HERE/.cache"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Pinned upstream build --------------------------------------------------
TMC_REPO="lorencouse/tmc"
TMC_TAG="${TMC_TAG:-v0.8.3-sp4}"
TMC_ASSET="tmc-multi-linux-arm64-${TMC_TAG}.tar.gz"
TMC_SHA256="ee01c50eaa390e7a6bc50dd369c7a8dd9cb85f19f98c18517d204aa50d957eb9"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

mkdir -p "$DIST" "$CACHE"

# 1. Obtain tmc_pc -------------------------------------------------------
if [ -n "${TMC_BINARY:-}" ]; then
  echo "==> using local binary: $TMC_BINARY"
  cp "$TMC_BINARY" "$STAGE/tmc_pc"
else
  bin_cache="$CACHE/tmc_pc-$TMC_TAG"
  if [ ! -f "$bin_cache" ]; then
    url="https://github.com/$TMC_REPO/releases/download/$TMC_TAG/$TMC_ASSET"
    echo "==> downloading $url"
    curl -fL --progress-bar -o "$CACHE/$TMC_ASSET" "$url"
    tar xzf "$CACHE/$TMC_ASSET" -C "$CACHE"
    mv "$CACHE/tmc_pc" "$bin_cache"
    rm -f "$CACHE/$TMC_ASSET"
  fi
  cp "$bin_cache" "$STAGE/tmc_pc"
fi

got="$(sha256_of "$STAGE/tmc_pc")"
if [ "$got" != "$TMC_SHA256" ]; then
  echo "!! tmc_pc SHA-256 mismatch" >&2
  echo "   expected $TMC_SHA256" >&2
  echo "   got      $got" >&2
  [ -n "${TMC_BINARY:-}" ] && echo "   (using a local TMC_BINARY -- update TMC_SHA256 if intentional)" >&2
  exit 1
fi
echo "==> tmc_pc verified ($got)"

# 2. Stage the port tree -------------------------------------------------
cp -R "$HERE/port/." "$STAGE/"
mv "$STAGE/tmc_pc" "$STAGE/picori/tmc_pc"
chmod +x "$STAGE/picori/tmc_pc" "$STAGE/Legend of Zelda - The Minish Cap.sh"

# Stamp the version so an installed copy can be identified on-device.
printf '%s\n' "$VERSION" > "$STAGE/picori/version.txt"

# Refuse to ship a ROM even if one is sitting in the working tree.
find "$STAGE" -iname '*.gba' -print -delete | sed 's/^/!! removed stray ROM: /'

missing=0
for f in "Legend of Zelda - The Minish Cap.sh" picori/tmc_pc picori/config.json \
         picori/tmc_pc.gptk picori/picori-weston.ini picori/port.json \
         picori/gameinfo.xml picori/README.md picori/LICENSE; do
  [ -e "$STAGE/$f" ] || { echo "!! missing: $f" >&2; missing=1; }
done
for f in picori/screenshot.png picori/cover.png; do
  [ -e "$STAGE/$f" ] || echo "   note: $f absent (needed before a PortMaster submission)"
done
[ "$missing" -eq 0 ] || exit 1

# 3. Zip -----------------------------------------------------------------
out="$DIST/picori-$VERSION.zip"
rm -f "$out"
( cd "$STAGE" && zip -q -r -X "$out" . -x '.DS_Store' -x '__MACOSX/*' )

echo "==> $out"
ls -lh "$out" | awk '{print "    size: "$5}'
echo "    sha256: $(sha256_of "$out")"
