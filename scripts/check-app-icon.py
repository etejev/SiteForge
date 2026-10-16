#!/usr/bin/env python3
"""Verify the approved static macOS icon catalog without opening project files in XCTest."""

import hashlib
import importlib.util
import json
import struct
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "SiteForge/Assets.xcassets/AppIcon.appiconset"
SOURCE = ROOT / "docs/design-assets/siteforge-app-icon-sf-gradient-approved-v2.png"
APPROVED_SOURCE_SHA256 = "9baa1876ffa52edd5cc2d591b582d5c02eb9b4a1aafbada64b5e24f4a7fe9070"


def load_packager():
    spec = importlib.util.spec_from_file_location(
        "siteforge_package_app_icon", ROOT / "scripts/package_app_icon.py"
    )
    if spec is None or spec.loader is None:
        raise ValueError("Unable to load deterministic AppIcon packager")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def png_dimensions_and_color(path: Path) -> tuple[int, int, int]:
    with path.open("rb") as image:
        header = image.read(26)
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"Invalid PNG: {path.relative_to(ROOT)}")
    width, height = struct.unpack(">II", header[16:24])
    return width, height, header[25]


def main() -> None:
    if not SOURCE.is_file():
        raise ValueError("Approved icon source is missing")
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != APPROVED_SOURCE_SHA256:
        raise ValueError("Approved v2 icon source bytes differ from owner-supplied artwork")
    packager = load_packager()
    with Image.open(SOURCE) as source_image:
        source_rgba = source_image.convert("RGBA")
        cutout = packager.transparent_exterior(source_image)
    if source_rgba.size != (1254, 1254):
        raise ValueError("Approved v2 icon source dimensions differ")
    if cutout.getpixel((0, 0))[3] != 0:
        raise ValueError("Exterior matte remains opaque")
    enclosed_white = [
        (x, y)
        for y in range(source_rgba.height)
        for x in range(source_rgba.width)
        if min(source_rgba.getpixel((x, y))[:3]) >= 245
        and cutout.getpixel((x, y))[3] == 255
    ]
    if len(enclosed_white) < 100_000:
        raise ValueError("Enclosed white SF artwork was not preserved")
    images = json.loads((CATALOG / "Contents.json").read_text())["images"]
    expected = {(points, scale) for points in (16, 32, 128, 256, 512) for scale in (1, 2)}
    actual = set()
    for image in images:
        if image["idiom"] != "mac":
            raise ValueError("AppIcon catalog contains a non-mac entry")
        points = int(image["size"].split("x")[0])
        scale = int(image["scale"].removesuffix("x"))
        if image["size"] != f"{points}x{points}" or (points, scale) not in expected:
            raise ValueError("Unexpected AppIcon size or scale")
        if (points, scale) in actual:
            raise ValueError("Duplicate AppIcon size and scale")
        actual.add((points, scale))
        path = CATALOG / image["filename"]
        if png_dimensions_and_color(path) != (points * scale, points * scale, 6):
            raise ValueError(f"AppIcon dimensions or RGBA format differ: {path.name}")
        expected_image = cutout.resize(
            (points * scale, points * scale), Image.Resampling.LANCZOS
        )
        with Image.open(path) as packaged_image:
            if ImageChops.difference(packaged_image.convert("RGBA"), expected_image).getbbox():
                raise ValueError(f"Packaged rendition is not the deterministic v2 transform: {path.name}")
    if actual != expected:
        raise ValueError("AppIcon catalog is missing a required macOS size")
    project = (ROOT / "SiteForge.xcodeproj/project.pbxproj").read_text()
    if project.count("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;") != 2:
        raise ValueError("Both app configurations must select AppIcon")
    if "Assets.xcassets in Resources" not in project:
        raise ValueError("AppIcon asset catalog is not in app resources")
    print("Approved app icon catalog checks passed.")


if __name__ == "__main__":
    main()
