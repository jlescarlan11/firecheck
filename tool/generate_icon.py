"""Generate FireCheck launcher icon (1024x1024 PNG).

Design: vibrant red-orange background, stylized white flame silhouette.
Run with: .icon_venv/bin/python tool/generate_icon.py
"""
from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "icon"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Colors
BG_TOP = (232, 74, 27)      # vivid orange-red
BG_BOTTOM = (175, 32, 16)   # deeper red at bottom
FLAME_OUTER = (255, 255, 255)
FLAME_INNER = (255, 214, 122)  # warm yellow center


def radial_gradient(size: int, inner: tuple[int, int, int], outer: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (size, size), outer)
    px = img.load()
    cx = cy = size / 2
    max_r = math.hypot(cx, cy)
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / max_r
            d = min(1.0, d)
            # ease toward outer color
            t = d ** 1.4
            r = int(inner[0] * (1 - t) + outer[0] * t)
            g = int(inner[1] * (1 - t) + outer[1] * t)
            b = int(inner[2] * (1 - t) + outer[2] * t)
            px[x, y] = (r, g, b)
    return img


def flame_half_width(t: float, width: float) -> float:
    """Asymmetric flame envelope. t=0 base, t=1 tip.

    Wide near base, peak ~t=0.25, narrows to 0 at tip.
    """
    # base curve: pow function gives wider base, gradual taper to tip
    envelope = (t ** 0.35) * ((1 - t) ** 1.1) * 2.8
    return max(0.0, width * envelope)


def flame_path(
    cx: float,
    base_y: float,
    height: float,
    width: float,
    steps: int = 360,
    base_round: float = 0.04,
) -> list[tuple[float, float]]:
    """Parametric closed flame silhouette with rounded base."""
    points: list[tuple[float, float]] = []
    # Right side: t from 0 (base) to 1 (tip)
    for i in range(steps + 1):
        t = i / steps
        y = base_y - t * height
        half_w = flame_half_width(t, width)
        points.append((cx + half_w, y))
    # Left side mirrored, reversed
    for i in range(steps + 1):
        t = (steps - i) / steps
        y = base_y - t * height
        half_w = flame_half_width(t, width)
        points.append((cx - half_w, y))
    return points


def render_icon() -> Image.Image:
    # Background: radial gradient
    bg = radial_gradient(SIZE, BG_TOP, BG_BOTTOM)
    img = bg.convert("RGBA")

    # Outer (white) flame
    outer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(outer)
    od.polygon(
        flame_path(cx=SIZE / 2, base_y=SIZE * 0.84, height=SIZE * 0.66, width=SIZE * 0.22),
        fill=FLAME_OUTER + (255,),
    )
    # soft glow halo
    glow = outer.filter(ImageFilter.GaussianBlur(radius=18))
    img.alpha_composite(glow)
    img.alpha_composite(outer)

    # Inner (warm yellow) flame, smaller, slightly higher base
    inner = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    idr = ImageDraw.Draw(inner)
    idr.polygon(
        flame_path(cx=SIZE / 2, base_y=SIZE * 0.79, height=SIZE * 0.46, width=SIZE * 0.13),
        fill=FLAME_INNER + (255,),
    )
    img.alpha_composite(inner)

    return img


def render_foreground_only() -> Image.Image:
    """Adaptive icon foreground: flame on transparent background, with safe-zone padding.

    Android adaptive icons crop to 66% safe zone; keep flame within 0.55 of canvas.
    """
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    outer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(outer)
    od.polygon(
        flame_path(cx=SIZE / 2, base_y=SIZE * 0.74, height=SIZE * 0.50, width=SIZE * 0.18),
        fill=FLAME_OUTER + (255,),
    )
    img.alpha_composite(outer)
    inner = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    idr = ImageDraw.Draw(inner)
    idr.polygon(
        flame_path(cx=SIZE / 2, base_y=SIZE * 0.70, height=SIZE * 0.36, width=SIZE * 0.10),
        fill=FLAME_INNER + (255,),
    )
    img.alpha_composite(inner)
    return img


if __name__ == "__main__":
    icon = render_icon()
    icon_path = OUT_DIR / "app_icon.png"
    icon.save(icon_path, format="PNG")
    print(f"Wrote {icon_path}")

    fg = render_foreground_only()
    fg_path = OUT_DIR / "app_icon_foreground.png"
    fg.save(fg_path, format="PNG")
    print(f"Wrote {fg_path}")
