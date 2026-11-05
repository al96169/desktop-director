"""Generate assets/ddir.ico — Desktop Director tray/app icon.

Design: deep navy rounded square (the "stage"), three tiled columns (the product's
1/2/3-column layout) in cyan / amber / white, with a thin baseline. Readable at 16 px.
"""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "assets"
OUT.mkdir(exist_ok=True)

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# rounded stage
pad, radius = 24, 210
d.rounded_rectangle([pad, pad, S - pad, S - pad], radius=radius, fill=(11, 18, 32, 255),
                    outline=(30, 41, 59, 255), width=18)

# three columns (equal width, 16 px gap at 1024 scale -> ~4%)
left, right = 150, S - 150
gap = 44
col_w = (right - left - 2 * gap) // 3
top, bottom = 250, 800
colors = [(34, 211, 238, 255), (245, 158, 11, 255), (226, 232, 240, 255)]
for i, color in enumerate(colors):
    x0 = left + i * (col_w + gap)
    d.rounded_rectangle([x0, top, x0 + col_w, bottom], radius=28, fill=color)

# baseline: a "director's slate" line under the columns
d.rounded_rectangle([left, 860, right, 892], radius=16, fill=(148, 163, 184, 255))

img.save(OUT / "ddir-256.png")
sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)]
img.resize((256, 256), Image.LANCZOS).save(OUT / "ddir.ico", format="ICO", sizes=sizes)
preview = Image.new("RGBA", (320, 160), (15, 23, 42, 255))
preview.alpha_composite(img.resize((128, 128), Image.LANCZOS), (16, 16))
preview.alpha_composite(img.resize((32, 32), Image.LANCZOS), (170, 40))
preview.alpha_composite(img.resize((16, 16), Image.LANCZOS), (170, 90))
preview.save(OUT / "ddir-preview.png")
print("wrote", OUT / "ddir.ico", (OUT / "ddir.ico").stat().st_size, "bytes")
