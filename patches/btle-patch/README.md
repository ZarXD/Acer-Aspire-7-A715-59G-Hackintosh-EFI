# BTLE Patch Sources

Archived source files for custom Intel Bluetooth Low Energy advertising / scan patches (`BTLEAdvFixup.kext` / `IntelBTPatcher` experiments).

Active EFI configuration loads `BTLEAdvFixup.kext` (0.9.3) with boot-args `-btleadv -btlenoscan`, paired with `IntelBluetoothFirmware.kext` (2.5.0) and `BlueToolFixup.kext` (2.7.3).

## Files

- `BTLEAdvHci.hpp` — HCI command definitions and helper structures
- `BTLEAdvPatches.hpp` — Bluetooth LE advertising patch hooks
- `IntelBTPatcher.cpp` — Intel BT patcher implementation
- `kern_start.cpp` — Lilu plugin entry point
