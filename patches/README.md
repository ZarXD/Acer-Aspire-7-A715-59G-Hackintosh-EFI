# Custom Patches & Manually Built Sources

This directory archives every manually patched or locally compiled component used alongside `EFI/` so that everything can be reproduced from source after a clean macOS reinstall.

| Directory | Component | Purpose |
| --- | --- | --- |
| [SMCSuperIO/](SMCSuperIO/) | Custom `SMCSuperIO.kext` (VirtualSMC 1.3.9) | Clevo EC fan/temp/RGB backend, DCHU `CLV0001` hotkey notifier, 9 OEM color presets, boot white-LED suppression, exact `0xF4`/`0xE0` 0% off sequence |
| [ACPI/](ACPI/) | Custom SSDT `.dsl` sources | `SSDT-CLEVOSENSE.dsl` (WMI/ECMD + Fn hotkeys), `SSDT-DGPU-NEGT.dsl` (RTX 3050 RTD3 D3 Cold), `SSDT-GPRW.dsl` (instant-wake fix) |
| [btle-patch/](btle-patch/) | Custom BTLE patch sources | Intel Bluetooth LE advertising / scan patch sources |
| [nullmoth/](nullmoth/) | NullMoth NVRM build & config | `build_nvrm_only.sh`, `install_nvrm_jigen.sh`, `NMLibVal-Info.plist`, and `/Library/GPUBundles/nvmtl-allow.txt` |

For ClevoSense (`NitroEC.kext`, `nitrod`, `NitroSense.app`), see the dedicated repository: [ZarXD/ClevoSense-macOS](https://github.com/ZarXD/ClevoSense-macOS).
