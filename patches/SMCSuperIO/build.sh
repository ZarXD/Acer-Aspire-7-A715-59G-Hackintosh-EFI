#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VSMC_DIR="${VSMC_DIR:-$HOME/VirtualSMC}"
LILU_KEXT="${LILU_KEXT:-$HOME/Hackintosh-XPS13Plus-IrisXe-Tahoe/build/deps/Lilu.kext}"
SDK="${SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
OUT_DIR="$SCRIPT_DIR/build"
OBJ_DIR="$OUT_DIR/obj"
KEXT_OUT="$OUT_DIR/SMCSuperIO.kext"

if [ ! -d "$VSMC_DIR/Sensors/SMCSuperIO" ]; then
    echo "ERROR: VirtualSMC tree not found at $VSMC_DIR"
    echo "Clone it first: git clone https://github.com/acidanthera/VirtualSMC.git \"$VSMC_DIR\""
    exit 1
fi

if [ ! -d "$LILU_KEXT/Contents/Resources/Headers" ]; then
    echo "ERROR: Lilu.kext SDK headers not found at $LILU_KEXT/Contents/Resources/Headers"
    echo "Set LILU_KEXT=/path/to/Lilu.kext (Debug release with Headers) and re-run."
    exit 1
fi

if [ ! -d "$SDK" ]; then
    SDK="$(xcrun --show-sdk-path)"
    echo "WARN: MacOSX15.4.sdk not found; falling back to $SDK"
fi

echo "== 1. Syncing patched SMCSuperIO sources into $VSMC_DIR =="
for f in ECDevice.cpp ECDeviceGeneric.cpp ECDeviceGeneric.hpp SMCSuperIO.cpp SuperIODevice.cpp; do
    cp "$SCRIPT_DIR/$f" "$VSMC_DIR/Sensors/SMCSuperIO/$f"
done

rm -rf "$OBJ_DIR" "$KEXT_OUT"
mkdir -p "$OBJ_DIR" "$KEXT_OUT/Contents/MacOS"

CFLAGS=(
    -arch x86_64
    -mmacosx-version-min=10.7
    -isysroot "$SDK"
    -mkernel
    -fapple-kext
    -std=c++17
    -O2
    -fno-builtin
    -fno-common
    -fno-rtti
    -fno-exceptions
    -fno-stack-protector
    -nostdinc
    -DKERNEL
    -DKERNEL_PRIVATE
    -DDRIVER_PRIVATE
    -DAPPLE
    -DNeXT
    "-I$SDK/System/Library/Frameworks/Kernel.framework/Headers"
    "-I$SDK/System/Library/Frameworks/Kernel.framework/PrivateHeaders"
    "-I$LILU_KEXT/Contents/Resources/Headers"
    "-I$VSMC_DIR/VirtualSMCSDK"
    "-I$VSMC_DIR/Sensors/SMCSuperIO"
)

SRC_DIR="$VSMC_DIR/Sensors/SMCSuperIO"
SRCS=(
    "$SRC_DIR/SMCSuperIO.cpp"
    "$SRC_DIR/SuperIODevice.cpp"
    "$SRC_DIR/Devices.cpp"
    "$SRC_DIR/ECDevice.cpp"
    "$SRC_DIR/ECDeviceDebug.cpp"
    "$SRC_DIR/ECDeviceGeneric.cpp"
    "$SRC_DIR/ECDeviceNUC.cpp"
    "$SRC_DIR/FintekDevice.cpp"
    "$SRC_DIR/ITEDevice.cpp"
    "$SRC_DIR/NuvotonDevice.cpp"
    "$SRC_DIR/WinbondDevice.cpp"
    "$SRC_DIR/WinbondFamilyDevice.cpp"
)

echo "== 2. Compiling SMCSuperIO objects =="
OBJS=()
for src in "${SRCS[@]}"; do
    base="$(basename "$src" .cpp)"
    obj="$OBJ_DIR/$base.o"
    clang++ "${CFLAGS[@]}" -c "$src" -o "$obj"
    OBJS+=("$obj")
done

# Compile kext info entry stub
cat <<'EOF' > "$OBJ_DIR/kmod_info.c"
#include <mach/mach_types.h>

extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);

__attribute__((visibility("default")))
KMOD_EXPLICIT_DECL(ru.joedm.SMCSuperIO, "1.3.9", _start, _stop)

__private_extern__ kmod_start_func_t *_realmain = 0;
__private_extern__ kmod_stop_func_t *_antimain = 0;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOF

clang -arch x86_64 -mmacosx-version-min=10.7 -isysroot "$SDK" \
    -mkernel -fapple-kext -O2 -fno-builtin -fno-common -fno-stack-protector -nostdinc \
    -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT \
    "-I$SDK/System/Library/Frameworks/Kernel.framework/Headers" \
    -c "$OBJ_DIR/kmod_info.c" -o "$OBJ_DIR/kmod_info.o"
OBJS+=("$OBJ_DIR/kmod_info.o")

echo "== 3. Linking SMCSuperIO kext binary =="
clang++ -arch x86_64 -mmacosx-version-min=10.7 -isysroot "$SDK" \
    -mkernel -fapple-kext -nostdlib -lkmodc++ -lkmod -lcc_kext \
    -Xlinker -kext \
    "${OBJS[@]}" \
    -o "$KEXT_OUT/Contents/MacOS/SMCSuperIO"

cp "$SCRIPT_DIR/Info.plist" "$KEXT_OUT/Contents/Info.plist"

echo "== 4. Verifying kernel ABI symbols =="
if nm -u "$KEXT_OUT/Contents/MacOS/SMCSuperIO" | grep -E '___(strncpy|memcpy|memset|strcpy)_chk|withPhysicalAddressEjjj'; then
    echo "ERROR: Invalid non-kernel symbols detected!"
    exit 1
fi

echo "OK: Built $KEXT_OUT"
ls -lh "$KEXT_OUT/Contents/MacOS/SMCSuperIO"
