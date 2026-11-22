# Acer Aspire 7 A715-59G — macOS OpenCore EFI

OpenCore EFI, custom patches, and post-install notes for the **Acer Aspire 7 A715-59G** (Clevo ODM `Kelilu_RTH`, Intel Core i5-13420H + Intel Iris Xe + NVIDIA RTX 3050 6GB Laptop) running **macOS Tahoe 26.7.2 (25G332)**.

Companion EC/fan/RGB control stack: [ClevoSense-macOS](https://github.com/ZarXD/ClevoSense-macOS).

## Specs

| Component | Hardware | Driver / Notes |
| --- | --- | --- |
| Laptop | Acer Aspire 7 A715-59G (Clevo `Kelilu_RTH`) | SMBIOS `MacBookPro16,2` |
| CPU | Intel Core i5-13420H (4P + 4E, 12 threads) | `IntelHybridCores` (`hcmode=4`) + `HybridPM` + `SSDT-PLUG-ALT` |
| iGPU | Intel Iris Xe (`0xa7a8`, 1536 MB, Metal 2) | `WhateverXe` 0.8.3 + `/Library/Extensions/AppleIntelTGL*` + `/Library/GPUBundles/AppleIntelTGL*` |
| Display | 15.6" 1920x1080 @ 144Hz eDP | `SSDT-PNLF` + `BrightnessKeys` |
| dGPU | NVIDIA GeForce RTX 3050 6GB Laptop (`0x25ac`) | NullMoth `NVRM` / `NVAccel` / `NVRMFB` / `NVRMAGDC` + `NVMTLDriver` + `SMCNvidiaGPU` (`nvrtd3=2`) |
| Audio | Realtek ALC256 + NVIDIA HDMI/DP 8ch | `SimpleHDA` + `AppleALC` (`layout-id=13`) + `VerbStub` + `ComboJack` (ALC256); `NMXAudio` scoped to `0x229110de` (NVIDIA HDMI/DP) |
| Wi-Fi | Intel Wi-Fi 6 (`en0`) | `ForbiddenItlwm` 0.6.0 (AWDL flags enabled) |
| Bluetooth | Intel Wireless Bluetooth | `IntelBluetoothFirmware` 2.5.0 + `BlueToolFixup` + `BTLEAdvFixup` |
| Ethernet | Realtek RTL8111 (`en1`) | `RealtekRTL8111` 2.4.2 |
| Touchpad / Keyboard | I2C HID Touchpad + PS/2 Keyboard | `VoodooI2C` / `VoodooI2CHID` + `VoodooPS2Controller` |
| EC / Fans / RGB | Clevo EC (`0x62`/`0x66`, DCHU `CLV0001`) | Custom `SMCSuperIO` 1.3.9 + `NitroEC` + `SSDT-CLEVOSENSE` + `ClevoSense-macOS` |
| Battery | Dual-byte EC battery registers | `SMCBatteryManager` + `ECEnabler` + `SSDT-ACFAKE` |
| Bootloader | OpenCore 1.0.9 | Non-verbose on SSD; keep `-v` on USB fallback |

## Status

| Feature | Status | Notes |
| --- | :---: | --- |
| Boot (Internal SSD) | ✅ | Silent non-verbose boot (`OpenCore 1.0.9`) |
| AMFI & TCC Permissions | ✅ | AMFI **ON** via `NMLibVal` + `NMAppFree` + `AMFIPass`; native macOS Privacy/TCC prompts work |
| Intel Iris Xe (Internal Panel) | ✅ | Full Metal 2 acceleration (`WhateverXe`), 1920x1080 @ 144Hz, smooth brightness keys |
| NVIDIA RTX 3050 6GB (Metal Offload) | ✅ | Whitelisted apps via `/Library/GPUBundles/nvmtl-allow.txt`; RTD3 D3 Cold (`nvrtd3=2`) powers off dGPU when idle |
| Audio (Speakers, Mic, 3.5mm ComboJack, HDMI) | ✅ | Auto-switching speakers/headphones + Headphones/Headset pop-up for IEM inline mic (`SimpleHDA` + `AppleALC` + `VerbStub` + `ComboJack`); NVIDIA HDMI/DP 8ch via `NMXAudio` |
| Wi-Fi (Intel AX) | ✅ | Native Wi-Fi + AWDL stack via `ForbiddenItlwm` 0.6.0 |
| Bluetooth | ✅ | Intel Wireless Bluetooth (`IntelBluetoothFirmware` + `BlueToolFixup` + `BTLEAdvFixup`) |
| AirDrop | ✅ | Working over `ForbiddenItlwm` AWDL + `BTLEAdvFixup` (`-btleadv -btlenoscan`) |
| Continuity (Handoff, Clipboard, Instant Hotspot) | ✅ | BLE timeout fixed with `-btlenoscan` while keeping AirDrop active |
| iServices (iCloud, iMessage, FaceTime, App Store) | ✅ | Working with valid generated `MacBookPro16,2` SMBIOS |
| DRM (Netflix / Widevine in Chrome) | ✅ | Working via `NMAppFree.kext` |
| Ethernet (Realtek RTL8111) | ✅ | Native Gigabit LAN |
| USB Ports & Webcam | ✅ | All USB-A / USB-C ports and internal Chicony USB 2.0 webcam working (`USBToolBox`) |
| Touchpad & Keyboard | ✅ | Multi-touch gestures (`VoodooI2CHID`), Fn brightness & volume keys |
| Clevo RGB Keyboard & Fn Hotkeys | ✅ | 9 OEM color presets, 0-100% brightness (0% completely off), boot white-LED suppression, `Fn + / * - +` bi-directional sync with `ClevoSense-macOS` |
| Fan Control & Power Profiles | ✅ | Live CPU/GPU RPM & temps, Quiet / Performance / Entertainment / Power Saving modes via `ClevoSense-macOS` |
| Battery & FlexiCharger | ✅ | Accurate battery %, AC detection, multi-level charge limit (60-100% via `WMEX` in `SSDT-CLEVOSENSE`) |
| CPU Power Management (Hybrid P+E) | ✅ | `IntelHybridCores` (`hcmode=4`) + `HybridPM` |
| Sleep / Wake (S3) | ⚠️ | Normal S3 sleep/wake works (`SSDT-GPRW`), but sleeping during a wedged GPU state can leave the screen dark; see [docs/RECOVERY.md](docs/RECOVERY.md) |
| Safari WebKit GPU Stability | ⚠️ | Heavy WebKit GPU sessions can occasionally deadlock `AppleIntelTGLGraphics`; Chromium/Firefox recommended for heavy workloads; see [docs/RECOVERY.md](docs/RECOVERY.md) |
| FairPlay / Apple TV+ DRM (Safari) | ❌ | Hardware FairPlay DRM is not supported on patched Intel Iris Xe (`WhateverXe`) |

## Repository layout

```text
.
├── EFI/                    # Ready-to-use OpenCore EFI (BOOT + OC)
├── docs/
│   ├── INSTALL.md          # BIOS settings, USB creation, macOS install, SSD deployment
│   ├── POSTINSTALL.md      # Full rebuild/reinstall guide (WhateverXe, NullMoth, ClevoSense, SMCSuperIO)
│   ├── RECOVERY.md         # USB recovery, macOS update recovery, known issues
│   └── images/             # System screenshots
├── patches/                # All manually modified sources and rebuild scripts
│   ├── ACPI/               # Custom SSDT .dsl sources + compile script
│   ├── SMCSuperIO/         # Clevo EC + DCHU RGB/Fn notifier patch + XNU ABI build script
│   ├── btle-patch/         # Custom Intel BTLE patch sources
│   └── nullmoth/           # NVRM build/install scripts, NMLibVal plist, nvmtl-allow.txt
└── scripts/                # EFI sync, health check, and nitrod deploy helpers
```

## Quick guide

1. Generate your own SMBIOS (`MacBookPro16,2` Serial, MLB, SystemUUID, ROM) in `EFI/OC/config.plist` before signing into iCloud.
2. Copy `EFI/` to a FAT32 USB flash drive first (add `-v` to `boot-args` on the USB copy for troubleshooting).
3. Install macOS Tahoe and follow [docs/INSTALL.md](docs/INSTALL.md).
4. Install user-space/system GPU bundles and ClevoSense using [docs/POSTINSTALL.md](docs/POSTINSTALL.md).
5. Deploy the verified EFI to the internal SSD ESP using `sudo ./scripts/sync-efi-to-ssd.sh`.

## Boot-args

Current SSD `boot-args` in `EFI/OC/config.plist` (add `-v` on USB when debugging):

| Flag | Purpose |
| --- | --- |
| `debug=0x100 keepsyms=1` | Keep kernel symbols and prevent instant reboot on kernel panic |
| `nvaccel=1 nvrtd3=2 -nvrmsmallbar nvsensoff=1` | Enable NullMoth RTX 3050 Metal acceleration, RTD3 D3 Cold power-off, small BAR support, and sensor polling off while suspended |
| `ipc_control_port_options=0 -allow3d -disablegfxfirmware -igfxdvmt -wex-va-renderer` | WhateverXe Iris Xe acceleration, DVMT bypass, and VA renderer flags |
| `hcmode=4` | `IntelHybridCores` P/E-core scheduling mode |
| `ssioec=generic` | Enable custom Clevo EC backend in `SMCSuperIO.kext` |
| `shda-lang=en` | `SimpleHDA` English audio device localization (with Apple-signed `AppleHDAHALPlugIn.bundle`) |
| `-btleadv -btlenoscan` | `BTLEAdvFixup` advertising fix without active scan stalling |
| `-itlawdl* itlawdlintcoal=4 itlawdltxqueue=4096 -itllog itlwm_lqmint=10 itlwm_scanout=240` | `ForbiddenItlwm` AWDL/Wi-Fi coexistence tuning |

## AMFI and library validation

AMFI stays **enabled** (no `amfi=0x80` / `amfi_get_out_of_my_way=1`):

- `NMLibVal.kext` permits unsigned/ad-hoc GPU Metal bundles (`AppleIntelTGL*`, `NVMTLDriver.bundle`).
- `NMAppFree.kext` exempts selected user apps from strict Mach IPC hardening.
- `AMFIPass.kext` handles Tahoe AMFI compatibility without disabling system-wide code signing enforcement.

## Dual GPU and RTD3 power management

- Internal display is wired to Intel Iris Xe (`WhateverXe.kext`).
- RTX 3050 6GB (`NVRM.kext`, built from `Thatisjigen/nvidia-macos-driver` `acer/current` with `SSDT-DGPU-NEGT.aml`) powers down to D3 Cold automatically (`nvrtd3=2`) when idle.
- `/Library/GPUBundles/nvmtl-allow.txt` whitelists heavy Metal/3D apps (Blender, Resolve, Final Cut Pro, Premiere, Steam, CrossOver, Whisky, Geekbench) to offload onto the RTX 3050 while keeping WindowServer and daily apps on Iris Xe.

## ClevoSense, RGB keyboard, and Fn hotkeys

Hardware EC control is split across three layers:

1. **`EFI/OC/ACPI/SSDT-CLEVOSENSE.aml`** — exposes the Clevo WMI/ECMD bridge (`WMBB` -> `WMAA` -> `ECMD`) and maps keyboard `Fn + / * - +` (`_Q0A`..`_Q0D`) to `Notify (CLV0001, 0xA0..0xA3)`.
2. **Custom `EFI/OC/Kexts/SMCSuperIO.kext`** — binds to `CLV0001`, suppresses Clevo's boot white backlight, implements the verified OEM Clevo BRG color + `0xF4`/`0xE0` off protocol, and syncs live state through SMC keys (`KLBR`, `KLRG`, `KLEF`, `KLON`, `CLFN`, `CLMD`). Source and build script are in [patches/SMCSuperIO/](patches/SMCSuperIO/).
3. **[ClevoSense-macOS](https://github.com/ZarXD/ClevoSense-macOS)** — `NitroEC.kext`, `nitrod` daemon, and menu bar UI for fan curves, power profiles, and bi-directional RGB control.

## Credits

- [Acidanthera](https://github.com/acidanthera) — OpenCore, Lilu, VirtualSMC, AppleALC, RestrictEvents, NVMeFix, BrightnessKeys
- [Thatisjigen](https://github.com/Thatisjigen) — [acer-nitro-anv15-52-macos](https://github.com/Thatisjigen/acer-nitro-anv15-52-macos), [NitroSense-macOS](https://github.com/Thatisjigen/NitroSense-macOS), [nvidia-macos-driver](https://github.com/Thatisjigen/nvidia-macos-driver), [NMAppFree](https://github.com/Thatisjigen/NMAppFree)
- [watchthelight-labs](https://github.com/watchthelight-labs) — NvGfx / NullMoth NVIDIA macOS driver stack
- WhateverXe / IntelHybridCores / ForbiddenItlwm / OpenIntelWireless / VoodooI2C / USBToolBox contributors
