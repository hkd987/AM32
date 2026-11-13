#!/usr/bin/env bash
# Reproducible build of the BZ-100 firmware from this repository (company-controlled AM32 fork).
#
#   bz100/build-repro.sh            build twice, compare, check against bz100/release-hashes.sha256
#   bz100/build-repro.sh --update   same, then rewrite bz100/release-hashes.sha256 from this build
#
# The committed tree at HEAD is exported with `git archive` into two different directories and built
# in each with the pinned compiler. The build passes only if .bin, .hex and .elf are bit-identical
# between the two directories and match the recorded release hashes.
set -euo pipefail
TARGET="BLUEZONE_100A_L431_CAN"
XPACK_URL="https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v10.3.1-2.3/xpack-arm-none-eabi-gcc-10.3.1-2.3-linux-x64.tar.gz"
XPACK_SHA256="559dcf1c2dfddac513110fe23da0ef254032c09967eaa901f075515d51818719"
XPACK_DIR="xpack-arm-none-eabi-gcc-10.3.1-2.3"
GCC_BIN_SHA256="a14075417c1aad6236a6203c8521408fa7d55d8b20e190c9c3b51bec6b5c153f"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${BZ_TOOLCHAIN_CACHE:-$REPO/.bz100-toolchain}"
WORK="${BZ_WORK:-$(mktemp -d)}"
UPDATE=0; [ "${1:-}" = "--update" ] && UPDATE=1
log() { echo "[bz100] $*"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- pinned compiler ---------------------------------------------------------------------------
mkdir -p "$CACHE"
ARCHIVE="$CACHE/$(basename "$XPACK_URL")"
if [ ! -f "$ARCHIVE" ] || [ "$(sha "$ARCHIVE")" != "$XPACK_SHA256" ]; then
    log "downloading compiler"
    curl -fSL --retry 3 -o "$ARCHIVE.part" "$XPACK_URL"
    [ "$(sha "$ARCHIVE.part")" = "$XPACK_SHA256" ] || { log "compiler archive checksum mismatch"; exit 1; }
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
[ -x "$CACHE/$XPACK_DIR/bin/arm-none-eabi-gcc" ] || tar -xzf "$ARCHIVE" -C "$CACHE"
TC="$CACHE/$XPACK_DIR"
[ "$(sha "$TC/bin/arm-none-eabi-gcc")" = "$GCC_BIN_SHA256" ] || { log "compiler binary does not match the pin"; exit 1; }
log "compiler: $("$TC/bin/arm-none-eabi-gcc" --version | head -1)"

# ---- two builds in two directories ---------------------------------------------------------------
COMMIT="$(git -C "$REPO" rev-parse HEAD)"
export SOURCE_DATE_EPOCH="$(git -C "$REPO" log -1 --format=%ct HEAD)"
VERSION="$(awk '/define VERSION_MAJOR/{a=$3} /define VERSION_MINOR/{b=$3} END{print a"."b}' "$REPO/Inc/version.h")"
BASE="AM32_${TARGET}_${VERSION}"
for d in first second/nested/deeper; do
    SRC="$WORK/$d/src"
    mkdir -p "$SRC"
    git -C "$REPO" archive --format=tar HEAD | tar -x -C "$SRC"
    make -C "$SRC" "$TARGET" "ARM_SDK_PREFIX=$TC/bin/arm-none-eabi-" "QUIET=" \
        "CC=$TC/bin/arm-none-eabi-gcc -ffile-prefix-map=$SRC=/am32 -ffile-prefix-map=$TC=/toolchain -Wa,--debug-prefix-map=$SRC=/am32 -save-temps -Wl,-Map=obj/$TARGET.map" \
        > "$WORK/$(echo "$d" | tr / _).log" 2>&1 || { tail -30 "$WORK/$(echo "$d" | tr / _).log"; exit 1; }
done
A="$WORK/first/src/obj"; B="$WORK/second/nested/deeper/src/obj"
STATUS=0
: > "$WORK/hashes.sha256"
for ext in bin hex elf; do
    ha="$(sha "$A/$BASE.$ext")"; hb="$(sha "$B/$BASE.$ext")"
    if [ "$ha" = "$hb" ]; then log "identical  $BASE.$ext  $ha"; else log "DIFFERENT  $BASE.$ext  $ha  $hb"; STATUS=1; fi
    echo "$ha  $BASE.$ext" >> "$WORK/hashes.sha256"
done
[ "$STATUS" = 0 ] || { log "FAIL: the two builds differ"; exit 1; }

# ---- recorded release hashes ------------------------------------------------------------------------
if [ "$UPDATE" = 1 ]; then
    cp "$WORK/hashes.sha256" "$REPO/bz100/release-hashes.sha256"
    log "release hashes updated"
elif ! diff -u "$REPO/bz100/release-hashes.sha256" "$WORK/hashes.sha256"; then
    log "FAIL: build does not match bz100/release-hashes.sha256 (run with --update if the source change is intended)"
    exit 1
fi
mkdir -p "$REPO/bz100/out"
cp "$A/$BASE.bin" "$A/$BASE.hex" "$A/$BASE.elf" "$WORK/hashes.sha256" "$REPO/bz100/out/"
log "PASS: commit $COMMIT builds reproducibly and matches the recorded hashes"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    { echo "### BZ-100 firmware, commit \`$COMMIT\`"; echo; echo '```'; cat "$WORK/hashes.sha256"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
fi
