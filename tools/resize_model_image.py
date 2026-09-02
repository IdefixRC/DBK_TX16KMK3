#!/usr/bin/env python3
"""Prepare a model PNG for the DBK_TX16KMK3 widget.

Keeps the aspect ratio, scales the image down (or up) to fit 250x150 px and
centres the result on a black background that matches the widget.
Optionally removes the image background first.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

WIDTH = 250
HEIGHT = 150


def remove_background(image: Image.Image) -> Image.Image:
    try:
        from rembg import remove
    except ModuleNotFoundError as error:
        raise RuntimeError(
            "To use --remove-background, install the dependency with: "
            "python3 -m pip install rembg"
        ) from error

    result = remove(image)
    return result.convert("RGBA")


def convert(source: Path, target: Path, strip_background: bool) -> None:
    with Image.open(source) as original:
        image = original.convert("RGBA")
        if strip_background:
            image = remove_background(image)
        image.thumbnail((WIDTH, HEIGHT), Image.Resampling.LANCZOS)

        # An RGB canvas without an alpha channel is more compatible with the
        # EdgeTX Bitmap.open() than PNGs Pillow writes with transparency.
        canvas = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
        position = (
            (WIDTH - image.width) // 2,
            (HEIGHT - image.height) // 2,
        )
        canvas.paste(image, position, image)

    target.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(target, "PNG", optimize=True)
    print(f"Created: {target} ({WIDTH}x{HEIGHT}px)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Creates a 250x150 px PNG for the DBK_TX16KMK3."
    )
    parser.add_argument("source", type=Path, help="original image (JPG, PNG, WEBP and so on)")
    parser.add_argument(
        "target",
        type=Path,
        nargs="?",
        help="output PNG (default: <name>_dbk.png)",
    )
    parser.add_argument(
        "--remove-background",
        action="store_true",
        help="remove the background automatically before writing the PNG",
    )
    args = parser.parse_args()

    if not args.source.is_file():
        parser.error(f"input file not found: {args.source}")

    target = args.target or args.source.with_name(f"{args.source.stem}_dbk.png")
    try:
        convert(args.source, target.with_suffix(".png"), args.remove_background)
    except RuntimeError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
