"""Package the owner-approved SF artwork into the static macOS AppIcon catalog.

Requires Pillow for this offline asset-authoring step; the application has no
runtime image-generation dependency. Only the edge-connected white matte is
removed, so the enclosed white SF lettering remains part of the source art.
"""

from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs/design-assets/siteforge-app-icon-sf-gradient-approved-v1.png"
DESTINATION = ROOT / "SiteForge/Assets.xcassets/AppIcon.appiconset"


def transparent_exterior(source: Image.Image) -> Image.Image:
    image = source.convert("RGBA")
    width, height = image.size
    pixels = image.load()
    pending = deque((x, y) for x in range(width) for y in (0, height - 1))
    pending.extend((x, y) for y in range(height) for x in (0, width - 1))
    visited = set()
    while pending:
        x, y = pending.popleft()
        if (x, y) in visited:
            continue
        visited.add((x, y))
        r, g, b, _ = pixels[x, y]
        if min(r, g, b) < 230:
            continue
        pixels[x, y] = (r, g, b, 0)
        if x > 0:
            pending.append((x - 1, y))
        if x + 1 < width:
            pending.append((x + 1, y))
        if y > 0:
            pending.append((x, y - 1))
        if y + 1 < height:
            pending.append((x, y + 1))
    return image


def main() -> None:
    with Image.open(SOURCE) as source:
        cutout = transparent_exterior(source)
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            size = points * scale
            suffix = "@2x" if scale == 2 else ""
            cutout.resize((size, size), Image.Resampling.LANCZOS).save(
                DESTINATION / f"icon_{points}x{points}{suffix}.png", optimize=True
            )


if __name__ == "__main__":
    main()
