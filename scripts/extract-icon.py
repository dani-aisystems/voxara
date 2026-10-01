"""Extracts the square macOS app icon from Brand/reference/voxara-brand-sheet.png.

Run with: uv run --with pillow python3 scripts/extract-icon.py
Output: Brand/logo/voxara-icon-1024.png (1024 canvas, 824 px rounded-square body, Apple icon grid).
"""
from PIL import Image, ImageChops, ImageDraw, ImageFilter

SHEET = "Brand/reference/voxara-brand-sheet.png"
OUT = "Brand/logo/voxara-icon-1024.png"
# Square region inside the sheet's large tile, inset past its uneven outer rim highlight.
CENTER_X, TOP, BOTTOM = 626, 68, 748
BODY, RADIUS, SS = 824, 185, 4  # body size, corner radius, supersampling factor


def rounded(size, radius, **kw):
    big = Image.new(kw.pop("mode", "L"), (size * SS, size * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, size * SS - 1, size * SS - 1), radius=radius * SS, **kw)
    return big.resize((size, size), Image.LANCZOS)


src = Image.open(SHEET).convert("RGBA")
side = BOTTOM - TOP
art = src.crop((CENTER_X - side // 2, TOP, CENTER_X - side // 2 + side, BOTTOM)).resize((BODY, BODY), Image.LANCZOS)

tile = Image.new("RGBA", (BODY, BODY), (0, 0, 0, 0))
tile.paste(art, (0, 0), rounded(BODY, RADIUS, fill=255))

# Thin warm rim: orange at top-right fading toward bottom-left, echoing the original glow.
rim = rounded(BODY, RADIUS, mode="RGBA", outline=(252, 108, 12, 255), width=3 * SS)
fade = Image.linear_gradient("L").rotate(-135).resize((BODY, BODY))
rim.putalpha(ImageChops.multiply(rim.getchannel("A"), fade.point(lambda v: int(30 + v * 0.7))))
tile = Image.alpha_composite(tile, rim)

canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle((100, 112, 924, 936), radius=RADIUS, fill=(0, 0, 0, 110))
canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(14)))
canvas.paste(tile, (100, 100), tile)
canvas.save(OUT)
print("wrote", OUT)

# Menu-bar template glyph: the bright V + waveform shape as a black alpha mask.
# Use the brightest channel (keeps the dim lower V and the orange wave), and ignore the outer
# border where the tile's glow lives.
border = 70
inner = art.crop((border, border, BODY - border, BODY - border)).convert("RGB")
r, g, b = inner.split()
peak = ImageChops.lighter(ImageChops.lighter(r, g), b)
alpha = peak.point(lambda v: 0 if v < 62 else min(255, (v - 62) * 5))
bbox = alpha.getbbox()
alpha = alpha.crop(bbox)
w, h = alpha.size
side = max(w, h)
square = Image.new("L", (side, side), 0)
square.paste(alpha, ((side - w) // 2, (side - h) // 2))
for px, name in ((18, "menubar-template.png"), (36, "menubar-template@2x.png")):
    a = square.resize((px, px), Image.LANCZOS)
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    img.putalpha(a)
    img.save(f"Brand/icons/{name}")
    print("wrote", name)
