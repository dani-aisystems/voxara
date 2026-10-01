#!/bin/zsh
# Builds Brand/icons/Voxara.icns from Brand/logo/voxara-icon-1024.png (CLT tools only).
# Regenerate the source PNG with: uv run --with pillow python3 scripts/extract-icon.py
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=Brand/logo/voxara-icon-1024.png
[[ -f $SRC ]] || { echo "missing $SRC"; exit 1; }
SET=$(mktemp -d)/Voxara.iconset
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SRC" --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$SRC" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Brand/icons/Voxara.icns
echo "wrote Brand/icons/Voxara.icns"
