#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

WORK="${WORK:-$HOME/build/nullmoth-jigen}"
NM="$WORK/src/nvidia-macos-driver"
VK_INC="$WORK/deps/Vulkan-Headers/include"
OUT="$WORK/out"

if [ ! -d "$NM/plugin" ]; then
    echo "ERROR: $NM/plugin not found. Clone Thatisjigen/nvidia-macos-driver (acer/current) first."
    exit 1
fi

if [ ! -f "$VK_INC/vulkan/vulkan.h" ]; then
    echo "== Cloning KhronosGroup/Vulkan-Headers =="
    mkdir -p "$WORK/deps"
    rm -rf "$WORK/deps/Vulkan-Headers"
    git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git "$WORK/deps/Vulkan-Headers"
fi

mkdir -p "$OUT"
echo "== Building NVMTLDriver from Thatisjigen/nvidia-macos-driver/plugin =="
(
    cd "$NM/plugin"
    xcrun clang -arch x86_64 -mmacosx-version-min=15.0 -bundle -fobjc-arc -O1 -DNVMTL_RELEASE=1 \
        -Wno-protocol -Wno-incomplete-implementation \
        -I"$VK_INC" \
        -o "$OUT/NVMTLDriver" \
        NVMTLDevice.m nvmtl_dlss.c dlss/elfhost.c dlss/lnxlibc.c \
        -framework Foundation -framework Metal -framework IOSurface -framework IOKit -framework CoreFoundation -framework MetalFX -liconv
)

vtool -show-build "$OUT/NVMTLDriver" | grep minos
strings "$OUT/NVMTLDriver" | grep -E 'IOSurfaceCopyGPUPolicies|GPUSelectionPolicy|preferRemovable|avoidRemovable' | sort -u

cat <<'NOTE'
OK: Built $OUT/NVMTLDriver

To install into /Library/GPUBundles/NVMTLDriver.bundle (requires sudo):
  sudo cp "$OUT/NVMTLDriver" /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver
  sudo chown -R root:wheel /Library/GPUBundles/NVMTLDriver.bundle
  sudo chmod -R go-w,a+rX /Library/GPUBundles/NVMTLDriver.bundle
  sudo chmod 755 /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver
  sudo codesign -f -s - --identifier com.nullmoth.NVMTLDriver /Library/GPUBundles/NVMTLDriver.bundle
  codesign --verify --deep --strict /Library/GPUBundles/NVMTLDriver.bundle
NOTE
