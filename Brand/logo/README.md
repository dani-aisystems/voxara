# Voxara logo

- `../reference/voxara-brand-sheet.png`: the brand sheet Daniel supplied (app icon, wordmark, small-size previews).
- `voxara-icon-1024.png`: the square macOS app icon (Apple icon grid), extracted from the sheet by
  `uv run --with pillow python3 scripts/extract-icon.py`. The same script writes the menu-bar template glyph.

To replace the logo: put a new sheet or icon here, adjust `scripts/extract-icon.py` if the layout differs,
then run `scripts/make-icon.sh` to rebuild `Brand/icons/Voxara.icns`.
