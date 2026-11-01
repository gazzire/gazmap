"""Gera os ícones do GAZMAP idênticos ao logo do site.

Logo do site: quadrado laranja #FF6B1A (34px, cantos 10px) com a montanha
branca do SVG (viewBox 24, 20px, centralizada). Mesmas cores e proporções.
"""
from pathlib import Path
from PIL import Image, ImageDraw

ORANGE = (0xFF, 0x6B, 0x1A, 255)
WHITE = (255, 255, 255, 255)
# Montanha do site (path "M2.5 19.5 9.5 6.5l3.6 6.4 2.2-3.4 6.2 10z", viewBox 24)
MOUNTAIN = [(2.5, 19.5), (9.5, 6.5), (13.1, 12.9), (15.3, 9.5), (21.5, 19.5)]
SS = 4  # supersampling para bordas suaves
OUT = Path(__file__).resolve().parent.parent / "assets/icon"


def mountain(draw, cx, cy, box):
    """Desenha a montanha num quadrado de lado `box` centrado em (cx, cy)."""
    s = box / 24
    pts = [(cx - box / 2 + x * s, cy - box / 2 + y * s) for x, y in MOUNTAIN]
    draw.polygon(pts, fill=WHITE)


def legacy(size):
    """Ícone clássico: quadrado arredondado laranja + montanha (como no site)."""
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, n - 1, n - 1], radius=n * 10 / 34, fill=ORANGE)
    mountain(d, n / 2, n / 2, n * 20 / 34)
    return img.resize((size, size), Image.LANCZOS)


def foreground(size):
    """Camada da frente do ícone adaptativo (108dp; área visível ~72dp)."""
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    visible = n * 72 / 108
    mountain(d, n / 2, n / 2, visible * 20 / 34)
    return img.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    legacy(1024).save(OUT / "icon_1024.png")
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        legacy(px).save(OUT / f"ic_launcher_{name}.png")
        foreground(int(px * 108 / 48)).save(OUT / f"ic_launcher_foreground_{name}.png")
    print("Ícones gerados em", OUT)
