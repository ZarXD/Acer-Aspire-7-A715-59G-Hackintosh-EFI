# NullMoth / NVRM Build & Configuration

Archived build scripts and configuration files for the NVIDIA GeForce RTX 3050 6GB Laptop (`0x25ac`) driver stack on macOS Tahoe.

## Files

- `build_nvrm_only.sh` — builds `NVRM.kext` from:
  - `Thatisjigen/nvidia-macos-driver` (`acer/current`, tested at `eb088b8`)
  - `NVIDIA/open-gpu-kernel-modules` (`620.70.06`, commit `e6a2e01`)
  - `watchthelight-labs/NvGfx` (`nvgfx-2.6.2`, commit `04f011e`)
- `install_nvrm_jigen.sh` — backs up existing `/Library/Extensions/NVRM.kext` + `AuxiliaryKernelExtensions.kc`, installs the freshly built `NVRM.kext`, and rebuilds the Auxiliary Kernel Collection via `kmutil`.
- `NMLibVal-Info.plist` — bundle metadata reference for `NMLibVal.kext` (`org.anv1552.NMLibVal`), which enables loading unsigned GPU Metal bundles while keeping AMFI enabled.
- `nvmtl-allow.txt` — installed at `/Library/GPUBundles/nvmtl-allow.txt` to whitelist specific Metal/3D/game apps onto the RTX 3050 while keeping WindowServer and daily apps on Intel Iris Xe.

See [docs/POSTINSTALL.md](../../docs/POSTINSTALL.md) for step-by-step build and installation instructions.
