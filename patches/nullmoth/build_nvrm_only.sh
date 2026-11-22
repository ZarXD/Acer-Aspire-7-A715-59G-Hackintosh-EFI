#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
WORK=/Users/izaa/build/nullmoth-jigen
NM=$WORK/src/nvidia-macos-driver
OGKM=$WORK/deps/open-gpu-kernel-modules
NVGFX=$WORK/deps/NvGfx
OBJ=$WORK/obj
OUT=$WORK/out
LOGS=$WORK/logs
JOBS=$(sysctl -n hw.logicalcpu)
CC=$(xcrun -f clang)
CXX=$(xcrun -f clang++)
SDKROOT=$(xcrun --show-sdk-path)
export SDKROOT
mkdir -p "$OBJ" "$OUT" "$LOGS"

echo "== 1. Applying NullMoth patches to open-gpu-kernel-modules =="
P=$NM/kexts/NVRM/patches
git -C "$OGKM" checkout -q -- .
: > "$OGKM/.nm-patches"
for f in $(cd "$P" && ls *.patch | LC_ALL=C sort); do
  ok=0
  for root in . src/nvidia-modeset; do
    ( cd "$OGKM/$root" && patch -t -p1 --fuzz=0 --dry-run < "$P/$f" ) > /dev/null 2>&1 || continue
    ( cd "$OGKM/$root" && patch -t -p1 --fuzz=0 --no-backup-if-mismatch < "$P/$f" ) > /dev/null || { echo "STOP: patch $f failed"; exit 1; }
    ok=1; break
  done
  [ $ok = 1 ] || { echo "STOP: $f does not apply"; exit 1; }
  echo "$f" >> "$OGKM/.nm-patches"
done
find "$OGKM/src" -name '*.orig' -delete
echo "Applied $(wc -l < "$OGKM/.nm-patches" | tr -d ' ') patches."

component() {
  local dir=$1 lib=$2; shift 2
  local d=$OGKM/src/$dir out=$OGKM/src/$dir/_out/Darwin_x86_64
  local cflags="-arch x86_64 -mmacosx-version-min=15.0 -mkernel -DNV_UNIX -DNV_BSD"
  local vars=( -f Makefile -f "$NVGFX/build/nvgfx/nvrm/darwin.mk" NV_VERBOSE=1 CC="$CC" CXX="$CXX" LD="$(xcrun -f ld)" AR="$(xcrun -f ar)"
    TARGET_OS=Darwin TARGET_ARCH=x86_64 NV_BUILD_USER=a71559g NV_BUILD_HOST=a71559g EXTRA_CFLAGS="$cflags" )
  mkdir -p "$out"
  echo "== 2. Building $dir (-j$JOBS) =="
  ( cd "$d" && nice make "${vars[@]}" "$@" -j"$JOBS" NVGFX_LIB="$lib" nvgfx-archive ) > "$LOGS/$dir.log" 2>&1 \
    || { grep -E "error:|\*\*\*" "$LOGS/$dir.log" | head -20; exit 1; }
  ( cd "$d" && make "${vars[@]}" "$@" -n -B nvgfx-objs 2> /dev/null ) | grep -E ' -c [^ ]+ -o ' > "$out/compile_cmds.sh"
  echo "$dir built: $out/$lib ($(stat -f %z "$out/$lib") bytes)"
}

component nvidia libnvkernel.a
component nvidia-modeset libnvkms.a

echo "== 3. Building NVRM.kext =="
S=$OBJ/nvrm/src
O=$OBJ/nvrm/out
rm -rf "$S" "$O"
mkdir -p "$S"
git -C "$NM" archive HEAD kexts build | tar -x -C "$S"
sed -i '' -E 's/^([a-z0-9-]+) [0-9]+$/\1 100000/' "$S/build/warnings.txt"
( cd "$S" && bash build/build_nvrm.sh kexts/NVRM "$OGKM" "$O" ) > "$LOGS/nvrm.log" 2>&1 \
  || { tail -30 "$LOGS/nvrm.log"; exit 1; }
cat "$LOGS/nvrm.log"

rm -rf "$OUT/NVRM.kext"
mkdir -p "$OUT/NVRM.kext/Contents/MacOS"
cp "$O/NVRM.kext/Contents/MacOS/NVRM" "$OUT/NVRM.kext/Contents/MacOS/NVRM"
cp /Library/Extensions/NVRM.kext/Contents/Info.plist "$OUT/NVRM.kext/Contents/Info.plist"
xattr -cr "$OUT/NVRM.kext" 2>/dev/null || true
chmod -R u+rwX,go+rX "$OUT/NVRM.kext"
echo "== DONE: $OUT/NVRM.kext =="
shasum -a 256 "$OUT/NVRM.kext/Contents/MacOS/NVRM"
