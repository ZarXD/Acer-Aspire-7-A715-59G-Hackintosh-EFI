# NullMoth / NVRM Build & Configuration

Archived build scripts and configuration files for the NVIDIA GeForce RTX 3050 6GB Laptop (`0x25ac`) driver stack on macOS Tahoe.

## Files

- `build_nvrm_only.sh` — builds `NVRM.kext` from:
  - `Thatisjigen/nvidia-macos-driver` (`acer/current`, tested at `eb088b8`)
  - `NVIDIA/open-gpu-kernel-modules` (`620.70.06`, commit `e6a2e01`)
  - `watchthelight-labs/NvGfx` (`nvgfx-2.6.2`, commit `04f011e`)
- `build_plugin_only.sh` — builds `NVMTLDriver` (`NVMTLDriver.bundle`) from `Thatisjigen/nvidia-macos-driver` (`acer/current`) with `IOSurfaceCopyGPUPolicies` / `GPUSelectionPolicy` support (`Automatic` / `Power saving` / `Performance` per-app GPU selection in ClevoSense).
- `install_nvrm_jigen.sh` — backs up existing `/Library/Extensions/NVRM.kext` + `AuxiliaryKernelExtensions.kc`, installs the freshly built `NVRM.kext`, and rebuilds the Auxiliary Kernel Collection via `kmutil`.
- `NMLibVal-Info.plist` — bundle metadata reference for `NMLibVal.kext` (`org.anv1552.NMLibVal`), which enables loading unsigned GPU Metal bundles while keeping AMFI enabled.
- `NMXAudio-Info.plist` & `scope_nmxaudio_hdmi.sh` — restricts `/Library/Extensions/NMXAudio.kext` to the NVIDIA RTX 3050 HDMI/DP audio device (`IOPCIMatch: 0x229110de`) and rebuilds `AuxiliaryKernelExtensions.kc` so Realtek ALC256 (`HDEF@1F,3`) remains handled by `SimpleHDA` + `AppleALC` + `VerbStub` + `ComboJack`.
- `nvmtl-allow.txt` — standard NullMoth allow-list (`!VoiceMemos`, `*`, `!WindowServer`) installed at `/Library/GPUBundles/nvmtl-allow.txt`; macOS platform binaries and `WindowServer` automatically stay on Intel Iris Xe while per-app GPU choices (`Automatic` / `Power saving` / `Performance`) are controlled through ClevoSense (`com.apple.gpu` `GPUSelectionPolicy`).

See [docs/POSTINSTALL.md](../../docs/POSTINSTALL.md) for step-by-step build and installation instructions.
