#!/usr/bin/env python3
"""Verify the approved static macOS icon catalog without opening project files in XCTest."""

import hashlib
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "SiteForge/Assets.xcassets/AppIcon.appiconset"
SOURCE = ROOT / "docs/design-assets/siteforge-app-icon-sf-gradient-approved-v1.png"
APPROVED_1024_SHA256 = "f437d1113f0c60504cd6d798403aea13a003f55ce7fbb76dcabe0dbc78201639"


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
        if points == 512 and scale == 2:
            if hashlib.sha256(path.read_bytes()).hexdigest() != APPROVED_1024_SHA256:
                raise ValueError("Packaged 1024 icon differs from approved gradient artwork")
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
