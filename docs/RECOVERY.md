# Recovery & Troubleshooting

## 1. Booting from the USB fallback

Always keep a working copy of `EFI/` on a FAT32 USB flash drive with `-v` enabled in `boot-args`.

If an SSD EFI change or kext update fails to boot:
1. Insert the USB fallback drive.
2. Press `F12` at power-on and select the USB drive.
3. Boot macOS, inspect logs or restore from the latest `~/BACKUP_SSD_EFI_*` folder created by `scripts/sync-efi-to-ssd.sh`.

## 2. Rebuilding AuxiliaryKernelExtensions.kc

After installing or updating any kext in `/Library/Extensions/` (such as `AppleIntelTGL*`, `NVRM.kext`, `NVAccel.kext`, or `NMXAudio.kext`), rebuild the Auxiliary Kernel Collection:

```bash
sudo kmutil create -n aux --volume-root / --allow-missing-kdk \
  --kernel /System/Library/Kernels/kernel \
  -B /System/Library/KernelCollections/BootKernelExtensions.kc \
  -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
  --repository /Library/Extensions \
  -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc.new -z
sudo mv -f /Library/KernelCollections/AuxiliaryKernelExtensions.kc.new \
  /Library/KernelCollections/AuxiliaryKernelExtensions.kc
```

Reboot after `kmutil` completes.

## 3. macOS minor updates

Before applying a macOS point update:
1. Confirm OpenCore and Lilu/WhateverXe/VirtualSMC/AMFIPass support the target build.
2. Back up `/Library/Extensions` and `/Library/GPUBundles`.
3. If `NMLibVal` or GPU bundles fail to load after an update, boot from USB with `-v` and re-run `kmutil create -n aux ...` above.

## 4. Known issues and workarounds

### Safari / WebKit GPU hang (`WhateverXe` + `AppleIntelTGLGraphics`)

Heavy WebKit GPU sessions in Safari can occasionally hit a `com.apple.WebKit.GPU` / `AppleIntelTGLGraphics` deadlock in `IOServiceTerminateThread`, causing WindowServer to freeze.

- **Do not put the laptop to sleep (`Fn+F12` / closing lid) while WindowServer is frozen.** S3 wake during a wedged iGPU context can leave the internal panel black and require a hard power-off (hold power button 5-10 seconds).
- For long downloads or heavy web workloads, Chromium-based browsers (Chrome, Brave, Arc) or Firefox avoid `com.apple.WebKit.GPU` and are significantly less prone to this deadlock.
- Inspect crash reports under `/Library/Logs/DiagnosticReports/WindowServer-*.ips` if a freeze occurs.

### `SMCSuperIO.kext` fails to load after a manual rebuild

XNU refuses to load `SMCSuperIO.kext` if compiled without kernel-ABI flags (producing userland fortified symbols such as `___strncpy_chk` or mismatched IOKit `withPhysicalAddress` signatures). Always compile using [patches/SMCSuperIO/build.sh](../patches/SMCSuperIO/build.sh) and check `nm -u` against stock Acidanthera `SMCSuperIO` before deploying to the SSD.

### Keyboard backlight white flash or stuck on

- Ensure `EFI/OC/ACPI/SSDT-CLEVOSENSE.aml` and the custom `EFI/OC/Kexts/SMCSuperIO.kext` are both enabled in `config.plist`, and `ssioec=generic` is present in `boot-args`.
- Confirm `NitroEC.kext` is loaded and `nitrod` is running:
  ```bash
  sudo launchctl list | grep nitrosense
  ```
