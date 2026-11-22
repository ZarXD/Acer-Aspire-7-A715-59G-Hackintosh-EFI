# Installation Guide

This guide covers BIOS preparation, creating a bootable USB installer, installing macOS Tahoe on the Acer Aspire 7 A715-59G, and deploying OpenCore to the internal SSD.

## 1. BIOS settings

Enter BIOS with `F2` at power-on (set a Supervisor Password temporarily if Secure Boot options are locked, then clear it afterward).

| Setting | Value |
| --- | --- |
| Secure Boot | Disabled |
| Fast Boot | Disabled |
| SATA / Storage Mode | AHCI (disable Intel VMD / RST if present; use `Ctrl+S` in Main tab to reveal hidden VMD toggle) |
| Wake on LAN | Disabled |
| TPM / PTT | Disabled or Enabled (tested working with default) |
| VT-d | Enabled |

## 2. Prepare OpenCore USB

1. Format a USB drive (16 GB+ for installer, or any FAT32 USB for EFI-only fallback) as GUID Partition Map.
2. Mount the USB EFI partition and copy `EFI/` from this repository into its root.
3. Generate unique `MacBookPro16,2` SMBIOS identifiers (`SystemSerialNumber`, `MLB`, `SystemUUID`, `ROM`) using GenSMBIOS and write them into `EFI/OC/config.plist` under `PlatformInfo -> Generic`.
4. For the USB copy, add `-v` to `NVRAM -> Add -> 7C436110-AB2A-4BBB-A880-FE41995C9F82 -> boot-args` so you have full verbose output if anything fails during setup.

Keep this USB drive around as your permanent recovery/testing EFI (`1401` fallback).

## 3. Install macOS

1. Boot from the USB drive (`F12` boot menu; enable `F12 Boot Menu` in BIOS first).
2. At the OpenCore picker, select the macOS Installer.
3. Open Disk Utility, format the target APFS container/volume on your internal NVMe SSD, and run the installer.
4. During the installation reboots, always boot through OpenCore and pick `macOS Installer`, then your newly created macOS volume.
5. Complete initial setup. Note that full iGPU/dGPU Metal acceleration requires installing `/Library/Extensions` and `/Library/GPUBundles` in [POSTINSTALL.md](POSTINSTALL.md).

## 4. Deploy EFI to the internal SSD

Once macOS boots cleanly from the USB drive, sync the verified EFI to the internal SSD ESP (`/dev/disk0s1`):

```bash
# Default: syncs ./EFI to /dev/disk0s1, backs up existing SSD EFI,
# preserves EFI/Microsoft and EFI/OEM, and strips -v for silent boot.
sudo ./scripts/sync-efi-to-ssd.sh
```

To sync from a mounted USB EFI instead:

```bash
sudo ./scripts/sync-efi-to-ssd.sh --source /Volumes/1401/EFI
```

To keep `-v` enabled on the SSD copy:

```bash
sudo ./scripts/sync-efi-to-ssd.sh --keep-verbose
```

## 5. Dual-boot with Windows 11

`scripts/sync-efi-to-ssd.sh` preserves `EFI/Microsoft` and `EFI/OEM` on `/dev/disk0s1`. OpenCore detects Windows Boot Manager automatically on the same ESP.

For consistent clock time between Windows and macOS, set Windows to use UTC hardware clock:

```powershell
reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
```
