#!/bin/bash
set -euo pipefail

CLEVOSENSE_DIR="${CLEVOSENSE_DIR:-$HOME/build/ClevoSense}"
BIN="$CLEVOSENSE_DIR/build/nitrod"

if [ ! -f "$BIN" ]; then
    echo "ERROR: $BIN not found. Build ClevoSense first."
    exit 1
fi

echo "Updating nitrod daemon from $BIN..."
sudo cp "$BIN" "/Library/Application Support/NitroSense/nitrod"
sudo pkill -9 nitrod || true
echo "OK: nitrod updated and restarted by launchd."
