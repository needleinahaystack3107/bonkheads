"""Decoder for SPRT sprite resources in Data.exe (format: docs/findings.md).

Used only to understand hitbox sizes and animation frames; decoded images
stay on the user's machine and are never committed.
"""
from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass

OP_ROW, OP_LITERAL, OP_SKIP = 1, 2, 3


@dataclass(frozen=True)
class Sprite:
    left: int
    top: int
    right: int
    bottom: int
    pixels: list[list[int | None]]  # palette indices, None = transparent

    @property
    def size(self) -> tuple[int, int]:
        return self.right - self.left, self.bottom - self.top


def decode(data: bytes) -> Sprite:
    """8-byte rect, then u32 records: high byte = op, low 24 bits = count.

    OP_ROW starts a new scanline (count = byte length of its records),
    OP_SKIP advances `count` transparent pixels, OP_LITERAL copies `count`
    palette bytes, padded to a 4-byte boundary.
    """
    left, top, right, bottom = struct.unpack_from("<4h", data)
    width, height = right - left, bottom - top
    rows: list[list[int | None]] = []
    p = 8
    while p + 4 <= len(data) and len(rows) <= height:
        word = struct.unpack_from("<I", data, p)[0]
        op, count = word >> 24, word & 0xFFFFFF
        p += 4
        if op == OP_ROW:
            rows.append([None] * width)
            x = 0
        elif op == OP_SKIP:
            x += count
        elif op == OP_LITERAL:
            row = rows[-1]
            for i, b in enumerate(data[p:p + count]):
                if 0 <= x + i < width:
                    row[x + i] = b
            x += count
            p += (count + 3) & ~3
        else:
            break
    rows += [[None] * width for _ in range(height - len(rows))]
    return Sprite(left, top, right, bottom, rows[:height])


def palette(data: bytes) -> list[tuple[int, int, int]]:
    """PALETTE resource: 256 RGB triplets."""
    return [tuple(data[i:i + 3]) for i in range(0, 768, 3)]


def to_rgba(sprite: Sprite, pal: list[tuple[int, int, int]]) -> tuple[int, int, bytes]:
    """Flatten to RGBA bytes; transparent pixels get alpha 0."""
    w, h = sprite.size
    out = bytearray()
    for row in sprite.pixels:
        for v in row:
            out += bytes((*pal[v], 255)) if v is not None else b"\0\0\0\0"
    return w, h, bytes(out)


def write_png(path, w: int, h: int, rgba: bytes) -> None:
    """Minimal PNG writer (stdlib only)."""
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    raw = b"".join(b"\0" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def contact_sheet(items: list[tuple[int, Sprite]], pal, cols: int = 16, cell: int = 100):
    """Lay sprites out in a grid (row-major, in the given order) -> (w, h, rgba)."""
    rows = (len(items) + cols - 1) // cols
    W, H = cols * cell, rows * cell
    buf = bytearray(b"\x30\x30\x38\xff" * (W * H))
    for i, (_, spr) in enumerate(items):
        ox, oy = (i % cols) * cell, (i // cols) * cell
        for y, row in enumerate(spr.pixels[:cell]):
            for x, v in enumerate(row[:cell]):
                if v is not None:
                    o = ((oy + y) * W + ox + x) * 4
                    buf[o:o + 4] = bytes((*pal[v], 255))
    return W, H, bytes(buf)
