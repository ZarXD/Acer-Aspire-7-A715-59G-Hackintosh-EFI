# Post-Install & Full Rebuild Guide

This document describes every manual component installed outside `EFI/` so a fresh macOS install can be restored to the exact working state from GitHub.

## 1. Prerequisites

Install Xcode Command Line Tools and `iasl` (for compiling ACPI `.dsl` sources if needed):

```bash
xcode-select --install
brew install acpica
```

Verify macOS power settings (prevents hibernation and unexpected wake loops):

```bash
sudo pmset -a hibernatemode 0 standby 0 autopoweroff 0 powernap 0 proximitywake 0 tcpkeepalive 0
```

## 2. Intel Iris Xe (WhateverXe + AppleIntelTGL)

`EFI/OC/Kexts/WhateverXe.kext` (0.8.3) is already loaded by OpenCore. System-level iGPU kexts and Metal/GL/VA bundles must be installed into `/Library/Extensions` and `/Library/GPUBundles`:

- `/Library/Extensions/`:
  - `AppleIntelTGLCompat.kext`
  - `AppleIntelTGLGraphics.kext`
  - `AppleIntelTGLGraphicsFramebuffer.kext`
- `/Library/GPUBundles/`:
  - `AppleIntelTGLGraphicsGLDriver.bundle`
  - `AppleIntelTGLGraphicsMTLDriver.bundle`
  - `AppleIntelTGLGraphicsVADriver.bundle`
  - `XeCompilerAdapter.bundle`
  - `XeOpenCL`

Install these using the WhateverXe release package matching `WhateverXe.kext` 0.8.3, then rebuild the Auxiliary Kernel Collection (step 3 below).

## 3. NVIDIA RTX 3050 6GB (NullMoth + Thatisjigen NVRM)

### 3.1 Install base NullMoth driver stack

Install the NullMoth 3.0 package into:

- `/Library/Extensions/`:
  - `NVRM.kext`
  - `NVAccel.kext`
  - `NVRMFB.kext`
  - `NVRMAGDC.kext`
  - `NMXAudio.kext`
- `/Library/GPUBundles/`:
  - `NVMTLDriver.bundle`
  - `nvmtl/`

### 3.2 Build and install RTD3-enabled `NVRM.kext`

Our laptop uses `Thatisjigen/nvidia-macos-driver` (`acer/current`) paired with `NVIDIA/open-gpu-kernel-modules` (`620.70.06`) and `watchthelight-labs/NvGfx` (`nvgfx-2.6.2`) so RTD3 D3 Cold (`nvrtd3=2`) powers down the RTX 3050 cleanly.

Scripts and reference files are archived in [patches/nullmoth/](../patches/nullmoth/).

```bash
mkdir -p ~/build/nullmoth-jigen/{src,deps}
git clone -b acer/current https://github.com/Thatisjigen/nvidia-macos-driver.git ~/build/nullmoth-jigen/src/nvidia-macos-driver
git clone --depth 1 --branch 620.70.06 https://github.com/NVIDIA/open-gpu-kernel-modules.git ~/build/nullmoth-jigen/deps/open-gpu-kernel-modules
git clone --depth 1 --branch nvgfx-2.6.2 https://github.com/watchthelight-labs/NvGfx.git ~/build/nullmoth-jigen/deps/NvGfx

cp patches/nullmoth/build_nvrm_only.sh ~/build/nullmoth-jigen/
cp patches/nullmoth/install_nvrm_jigen.sh ~/build/nullmoth-jigen/

bash ~/build/nullmoth-jigen/build_nvrm_only.sh
sudo bash ~/build/nullmoth-jigen/install_nvrm_jigen.sh
```

`install_nvrm_jigen.sh` backs up the previous `NVRM.kext` and `AuxiliaryKernelExtensions.kc`, installs the freshly built `NVRM.kext`, and rebuilds the Auxiliary Kernel Collection with `kmutil`.

### 3.3 Scope `NMXAudio.kext` to NVIDIA HDMI/DP only (for Realtek ALC256 + ComboJack)

By default, `NMXAudio.kext` matches all HDA controllers (`0x04030000&0xffff0000`) with `IOProbeScore = 5000`, hijacking Intel `HDEF@1F,3` (Realtek ALC256) from `SimpleHDA` + `AppleALC` and breaking auto jack switching and `ComboJack`.

Scope `NMXAudio.kext` exclusively to the RTX 3050 HDMI/DP audio controller (`0x229110de`) so ALC256 stays on `SimpleHDA` + `AppleALC` (`layout-id=13`) + `VerbStub` + `ComboJack`:

```bash
sudo ./patches/nullmoth/scope_nmxaudio_hdmi.sh
```

Ensure `SimpleHDA`'s Apple-signed `AppleHDAHALPlugIn.bundle` is installed in `/Library/Audio/Plug-Ins/SimpleHDA/` and `ComboJack` (`/usr/local/sbin/ComboJack`, `/Library/LaunchDaemons/com.XPS.ComboJack.plist`) is enabled:

```bash
sudo launchctl enable system/com.XPS.ComboJack
sudo launchctl bootstrap system /Library/LaunchDaemons/com.XPS.ComboJack.plist
```

### 3.4 Configure Metal offload whitelist (`nvmtl-allow.txt`)

Copy the whitelist so macOS WindowServer and daily apps stay on Iris Xe while heavy 3D/compute/game apps use the RTX 3050:

```bash
sudo cp patches/nullmoth/nvmtl-allow.txt /Library/GPUBundles/nvmtl-allow.txt
sudo chown root:wheel /Library/GPUBundles/nvmtl-allow.txt
sudo chmod 644 /Library/GPUBundles/nvmtl-allow.txt
```

## 4. ClevoSense-macOS (Fan control, power profiles, RGB keyboard)

Clone and install from [ZarXD/ClevoSense-macOS](https://github.com/ZarXD/ClevoSense-macOS):

```bash
git clone https://github.com/ZarXD/ClevoSense-macOS.git ~/build/ClevoSense
cd ~/build/ClevoSense
./install.sh
```

This builds and installs:
- `nitrod` daemon in `/Library/Application Support/NitroSense/nitrod` (managed by LaunchDaemon `com.nitrosense.daemon`)
- `NitroSense.app` in `/Applications/NitroSense.app`

Note: `NitroEC.kext` and `SSDT-CLEVOSENSE.aml` are already bundled in `EFI/OC/`. Whenever you rebuild `nitrod` locally, run `./scripts/update-nitrod.sh`.

## 5. Rebuilding custom `SMCSuperIO.kext` (optional)

Prebuilt `SMCSuperIO.kext` (1.3.9 with Clevo EC + DCHU `CLV0001` notifier + OEM RGB/Off commands) is already in `EFI/OC/Kexts/SMCSuperIO.kext`.

To rebuild from upstream VirtualSMC source using our archived patch and verified XNU 10.7 kernel ABI flags, see [patches/SMCSuperIO/README.md](../patches/SMCSuperIO/README.md) and run `patches/SMCSuperIO/build.sh`.

## 6. Recompiling custom ACPI SSDTs (optional)

Compiled `.aml` tables are already in `EFI/OC/ACPI/`. Sources for all custom tables (`SSDT-CLEVOSENSE.dsl`, `SSDT-DGPU-NEGT.dsl`, `SSDT-GPRW.dsl`) are archived in [patches/ACPI/](../patches/ACPI/):

```bash
./patches/ACPI/compile.sh
```

## 7. Verification after reboot

Run the health check script to verify loaded kexts and EC/SMC status:

```bash
./scripts/check-efi.sh
```

Verify both GPUs and RTD3 status:

```bash
system_profiler SPDisplaysDataType
kmutil showloaded --list-only | grep -E 'WhateverXe|NVRM|SMCSuperIO|NitroEC|NMLibVal|NMAppFree'
```
