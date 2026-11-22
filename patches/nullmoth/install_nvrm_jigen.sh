#!/bin/bash
set -euo pipefail
BACKUP="/Users/izaa/BACKUP_NVRM_30_STOCK_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP"
ditto /Library/Extensions/NVRM.kext "$BACKUP/NVRM.kext"
cp -p /Library/KernelCollections/AuxiliaryKernelExtensions.kc "$BACKUP/AuxiliaryKernelExtensions.kc.bak"

rm -rf /Library/Extensions/NVRM.kext
ditto /Users/izaa/build/nullmoth-jigen/out/NVRM.kext /Library/Extensions/NVRM.kext
chown -R root:wheel /Library/Extensions/NVRM.kext
chmod -R 755 /Library/Extensions/NVRM.kext

NEW_KC="/Library/KernelCollections/AuxiliaryKernelExtensions.kc.new"
rm -f "$NEW_KC"
kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions \
    -A "$NEW_KC" -z

mv -f "$NEW_KC" /Library/KernelCollections/AuxiliaryKernelExtensions.kc
echo "OK: Installed Thatisjigen NVRM.kext & rebuilt AuxiliaryKernelExtensions.kc (backup: $BACKUP)"
