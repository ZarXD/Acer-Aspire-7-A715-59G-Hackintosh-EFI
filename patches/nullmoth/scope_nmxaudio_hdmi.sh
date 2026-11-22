#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run with sudo."
    exit 1
fi

KEXT="/Library/Extensions/NMXAudio.kext"
if [ ! -f "$KEXT/Contents/Info.plist" ]; then
    echo "ERROR: $KEXT not found."
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"
BACKUP="$REAL_HOME/BACKUP_NMXAUDIO_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP"
ditto "$KEXT" "$BACKUP/NMXAudio.kext"
cp -p /Library/KernelCollections/AuxiliaryKernelExtensions.kc "$BACKUP/AuxiliaryKernelExtensions.kc.bak"
chown -R "$REAL_USER:staff" "$BACKUP" 2>/dev/null || true

python3 - <<'PY'
import plistlib
p = "/Library/Extensions/NMXAudio.kext/Contents/Info.plist"
with open(p, "rb") as f:
    pl = plistlib.load(f)
pl["IOKitPersonalities"]["HDAudio"]["IOPCIMatch"] = "0x229110de"
with open(p, "wb") as f:
    plistlib.dump(pl, f)
PY

plutil -lint "$KEXT/Contents/Info.plist"
chown -R root:wheel "$KEXT"
chmod -R 755 "$KEXT"

NEW_KC="/Library/KernelCollections/AuxiliaryKernelExtensions.kc.new"
rm -f "$NEW_KC"
kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions \
    -A "$NEW_KC" -z
mv -f "$NEW_KC" /Library/KernelCollections/AuxiliaryKernelExtensions.kc

echo "OK: NMXAudio scoped to NVIDIA HDMI/DP (0x229110de) & AuxiliaryKernelExtensions.kc rebuilt."
echo "Backup saved to: $BACKUP"
