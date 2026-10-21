"""Reads a table from an image with Tesseract (the `tesseract` program, installed on the
workflow's runner; TESSERACT can name it elsewhere).

Tesseract misreads a table's ruled lines as letters, so the long lines are found first
(pixel rows and columns that are mostly dark) and painted white; what is left reads as
plain lines of text, one per table row.
"""

from __future__ import annotations

import io
import os
import shutil
import subprocess

from PIL import Image, ImageDraw

# A pixel row (column) darker than this share is a ruled line.
ROW_LINE = 0.6
COLUMN_LINE = 0.7
DARK = 100  # grey levels below this are ink
LINE_WIDTH = 2  # pixels painted white on each side of a line


def tesseract() -> str | None:
    return os.environ.get("TESSERACT") or shutil.which("tesseract")


def available() -> bool:
    return tesseract() is not None


def without_lines(image: bytes) -> Image.Image:
    """The image in grey, with its ruled lines painted white."""
    grey = Image.open(io.BytesIO(image)).convert("L")
    width, height = grey.size
    ink = grey.point(lambda level: 255 if level < DARK else 0)
    rows = ink.resize((1, height), Image.Resampling.BOX).get_flattened_data()
    columns = ink.resize((width, 1), Image.Resampling.BOX).get_flattened_data()
    draw = ImageDraw.Draw(grey)
    for y, share in enumerate(rows):
        if share > 255 * ROW_LINE:
            draw.rectangle((0, y - LINE_WIDTH, width, y + LINE_WIDTH), fill=255)
    for x, share in enumerate(columns):
        if share > 255 * COLUMN_LINE:
            draw.rectangle((x - LINE_WIDTH, 0, x + LINE_WIDTH, height), fill=255)
    return grey


def table_text(image: bytes) -> str:
    """The table's text, one line per row."""
    program = tesseract()
    if program is None:
        raise RuntimeError("tesseract is not installed")
    png = io.BytesIO()
    without_lines(image).save(png, format="PNG")
    done = subprocess.run(
        [program, "stdin", "stdout", "--psm", "6"],
        input=png.getvalue(),
        capture_output=True,
        check=True,
        timeout=120,
    )
    return done.stdout.decode("utf-8", errors="replace")
