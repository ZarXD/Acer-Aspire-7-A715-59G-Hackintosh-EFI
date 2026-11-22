# Patched SMCSuperIO (Clevo EC + DCHU RGB/Fn)

Modified `Sensors/SMCSuperIO` source files based on upstream [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC) (commit `b5c62c2`, v1.3.9).

## What is patched

- **Clevo EC generic backend (`ssioec=generic`)** in `ECDeviceGeneric.cpp` / `ECDeviceGeneric.hpp`:
  - Direct Clevo EC (`0x62`/`0x66`) fan RPM and temperature sensors.
  - DCHU `CLV0001` ACPI notification listener (`0xA0`..`0xA3`) for `Fn + / * - +` keyboard backlight hotkeys (`SSDT-CLEVOSENSE.aml`).
  - Verified OEM Clevo ECMD protocol (reversed from `LedKeyboardSetting.exe` and `FnKey.exe`):
    - Color byte order: **BRG** (`Blue, Red, Green`) via `0xF0`.
    - Brightness 0% complete off: `0xF4000000` (`0xCA 0x06 0x00`) followed by `0xE0000007` (`0xC4 0x0C 0x00`).
    - Turn on: `0xE007F001` (`0xC4 0x0C 0x3F`) followed by `0xF4000000 | level`.
    - 9 OEM color presets and boot-time white LED suppression.
  - SMC key bridge (`KLBR`, `KLRG`, `KLEF`, `KLON`, `CLFN`, `CLMD`) for bi-directional sync with `ClevoSense-macOS`.
- **`Info.plist`**: adds `com.apple.iokit.IOACPIFamily` (`1.0.0d1`) to `OSBundleLibraries`.

## Files

- `virtualsmc-clevo.patch` — unified diff against `acidanthera/VirtualSMC` (`b5c62c2`).
- `ECDevice.cpp`, `ECDeviceGeneric.cpp`, `ECDeviceGeneric.hpp`, `SMCSuperIO.cpp`, `SuperIODevice.cpp` — full patched source files.
- `Info.plist` — kext bundle plist with `IOACPIFamily` dependency.
- `build.sh` — standalone kernel-ABI compiler script.

## Rebuilding

```bash
# Requires:
# 1. VirtualSMC checkout (defaults to ~/VirtualSMC)
# 2. Lilu.kext SDK headers (defaults to ~/Hackintosh-XPS13Plus-IrisXe-Tahoe/build/deps/Lilu.kext)
# 3. MacOSX15.4.sdk (or compatible CommandLineTools SDK)

./patches/SMCSuperIO/build.sh
```

The script outputs `SMCSuperIO.kext` in `patches/SMCSuperIO/build/SMCSuperIO.kext` and checks `nm -u` for forbidden userland symbols (`___strncpy_chk`, `___memcpy_chk`, etc.).
