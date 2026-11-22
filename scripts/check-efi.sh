#!/bin/bash
set -euo pipefail

echo "== macOS Version =="
sw_vers

echo ""
echo "== Boot Args =="
nvram boot-args 2>/dev/null || echo "(unavailable)"

echo ""
echo "== Key Loaded Kexts =="
kmutil showloaded --list-only 2>/dev/null | grep -E 'Lilu|VirtualSMC|SMCSuperIO|SMCBattery|SMCNvidia|NitroEC|WhateverXe|NVRM|NVAccel|NMXAudio|NMLibVal|NMAppFree|AMFIPass|ForbiddenItlwm|IntelHybridCores|HybridPM|BTLEAdvFixup' || true

echo ""
echo "== ClevoSense Daemon =="
launchctl list 2>/dev/null | grep -i nitrosense || sudo launchctl list 2>/dev/null | grep -i nitrosense || echo "(not running)"

echo ""
echo "== Displays / GPUs =="
system_profiler SPDisplaysDataType | grep -E 'Chipset Model|VRAM|Metal|Resolution' || true
