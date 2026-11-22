#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/EFI/OC/ACPI}"

if ! command -v iasl >/dev/null 2>&1; then
    echo "ERROR: iasl not found. Install with: brew install acpica"
    exit 1
fi

mkdir -p "$OUT_DIR"

for dsl in "$SCRIPT_DIR"/*.dsl; do
    base="$(basename "$dsl" .dsl)"
    echo "== Compiling $base.dsl -> $OUT_DIR/$base.aml =="
    iasl -tc -p "$OUT_DIR/$base" "$dsl"
    rm -f "$OUT_DIR/$base.hex"
done

echo "OK: Compiled custom SSDTs into $OUT_DIR"
ls -lh "$OUT_DIR"/SSDT-CLEVOSENSE.aml "$OUT_DIR"/SSDT-DGPU-NEGT.aml "$OUT_DIR"/SSDT-GPRW.aml
