#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_EFI="$REPO_ROOT/EFI"
ESP_DEV="/dev/disk0s1"
STRIP_VERBOSE=1

usage() {
    cat <<EOF
Usage: sudo $0 [options]

Options:
  --source <path>    Source EFI directory (default: $REPO_ROOT/EFI)
  --disk <dev>       Target ESP device (default: /dev/disk0s1)
  --keep-verbose     Keep -v in boot-args instead of stripping it
  --no-verbose       Strip -v from boot-args (default)
  -h, --help         Show this help message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --source) SRC_EFI="$2"; shift 2 ;;
        --disk) ESP_DEV="$2"; shift 2 ;;
        --keep-verbose) STRIP_VERBOSE=0; shift ;;
        --no-verbose) STRIP_VERBOSE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run with sudo."
    exit 1
fi

if [ ! -f "$SRC_EFI/OC/OpenCore.efi" ] || [ ! -f "$SRC_EFI/OC/config.plist" ]; then
    echo "ERROR: Invalid EFI source at $SRC_EFI"
    exit 1
fi

echo "== 1. Mounting target ESP ($ESP_DEV) =="
mkdir -p /Volumes/ESP
TARGET_MOUNT=$(mount | grep "^$ESP_DEV " | awk '{print $3}' || true)
if [ -z "$TARGET_MOUNT" ]; then
    diskutil mount -mountPoint /Volumes/ESP "$ESP_DEV" >/dev/null 2>&1 || mount_msdos "$ESP_DEV" /Volumes/ESP
    TARGET_MOUNT="/Volumes/ESP"
fi
echo "Mounted at: $TARGET_MOUNT"

echo "== 2. Backing up existing SSD EFI =="
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"
BACKUP_DIR="$REAL_HOME/BACKUP_SSD_EFI_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
if [ -d "$TARGET_MOUNT/EFI" ]; then
    cp -R "$TARGET_MOUNT/EFI" "$BACKUP_DIR/"
    chown -R "$REAL_USER:staff" "$BACKUP_DIR" 2>/dev/null || true
    echo "Backup saved to: $BACKUP_DIR"
fi

echo "== 3. Syncing BOOT and OC (preserving EFI/Microsoft and EFI/OEM) =="
mkdir -p "$TARGET_MOUNT/EFI"

rm -rf "$TARGET_MOUNT/EFI/BOOT"
mkdir -p "$TARGET_MOUNT/EFI/BOOT"
rsync -a --exclude='.DS_Store' --exclude='._*' "$SRC_EFI/BOOT/" "$TARGET_MOUNT/EFI/BOOT/"

rm -rf "$TARGET_MOUNT/EFI/OC"
mkdir -p "$TARGET_MOUNT/EFI/OC"
rsync -a --exclude='.DS_Store' --exclude='._*' --exclude='config.plist.bak*' --exclude='config.plist.backup*' "$SRC_EFI/OC/" "$TARGET_MOUNT/EFI/OC/"

if [ "$STRIP_VERBOSE" -eq 1 ]; then
    echo "== 4. Stripping -v for silent SSD boot =="
    python3 - "$TARGET_MOUNT/EFI/OC/config.plist" <<'PY'
import plistlib, sys

plist_path = sys.argv[1]
with open(plist_path, "rb") as f:
    pl = plistlib.load(f)

guid = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
nv_add = pl["NVRAM"]["Add"][guid]
tokens = [t for t in nv_add.get("boot-args", "").split() if t != "-v"]
nv_add["boot-args"] = " ".join(tokens)

nv_del = pl["NVRAM"]["Delete"].setdefault(guid, [])
if "boot-args" not in nv_del:
    nv_del.append("boot-args")

pl["Misc"]["Debug"]["AppleDebug"] = False
pl["Misc"]["Debug"]["Target"] = 0
pl["Misc"]["Debug"]["DisplayLevel"] = 0

with open(plist_path, "wb") as f:
    plistlib.dump(pl, f)
PY
fi

echo "== 5. Verifying integrity =="
plutil -lint "$TARGET_MOUNT/EFI/OC/config.plist"
test -f "$TARGET_MOUNT/EFI/BOOT/BOOTx64.efi"
test -f "$TARGET_MOUNT/EFI/OC/OpenCore.efi"
test -f "$TARGET_MOUNT/EFI/OC/ACPI/SSDT-CLEVOSENSE.aml"
test -f "$TARGET_MOUNT/EFI/OC/Kexts/SMCSuperIO.kext/Contents/MacOS/SMCSuperIO"
test -f "$TARGET_MOUNT/EFI/OC/Kexts/NitroEC.kext/Contents/MacOS/NitroEC"
ls -la "$TARGET_MOUNT/EFI"

echo "== 6. Unmounting ESP =="
sync
diskutil unmount "$ESP_DEV"
echo "OK: SSD EFI synced cleanly."
