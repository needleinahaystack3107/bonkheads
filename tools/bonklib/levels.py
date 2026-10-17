"""Decoders for the original level resources in Levels.exe.

Formats are documented once in docs/findings.md ("Original resource formats");
this module is the executable form of that section. All fields are
little-endian int16.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass

from .pe import PEImage

GRID_COLS, GRID_ROWS = 20, 30          # 32x16-pixel tiles on a 640x480 screen
TILE_W, TILE_H = 32, 16
SUBPIXELS = 16                          # positions/velocities are 1/16 pixel


@dataclass(frozen=True)
class TileMap:
    """BKMP: 600 uint16 tile codes stored column-major (x * 30 + y)."""
    tiles: tuple[int, ...]

    @classmethod
    def parse(cls, data: bytes) -> "TileMap":
        return cls(struct.unpack("<600H", data))

    def at(self, col: int, row: int) -> int:
        return self.tiles[col * GRID_ROWS + row]

    def rows(self) -> list[list[int]]:
        return [[self.at(c, r) for c in range(GRID_COLS)] for r in range(GRID_ROWS)]


@dataclass(frozen=True)
class Spawn:
    """One ENDT record (13 int16)."""
    kind: int        # enemy type id, see ENEMY_KINDS
    speed: int       # scaled by difficulty in 0x42209c
    unknown2: int
    vx: int          # initial x velocity; sign picks the left/right pipe
    unknown4: int
    unknown5: int
    unknown6: int
    points: int      # score for kicking it
    delay: int       # ticks before it emerges
    left_x: int      # pipe exit x (pixels) when vx > 0
    right_x: int     # pipe exit x when vx < 0
    left_y: int
    right_y: int


def parse_spawns(data: bytes) -> list[Spawn]:
    count = struct.unpack_from("<h", data)[0]
    return [Spawn(*struct.unpack_from("<13h", data, 2 + i * 26)) for i in range(count)]


@dataclass(frozen=True)
class World:
    """MLST (80 bytes): one "underworld" = 5 maps + boss, plus its physics.

    Offsets in comments are byte offsets the game reads (see findings.md).
    """
    raw: tuple[int, ...]

    @classmethod
    def parse(cls, data: bytes) -> "World":
        return cls(struct.unpack("<40h", data))

    maps = property(lambda s: s.raw[0:5])            # BKMP ids
    spawn_tables = property(lambda s: s.raw[6:11])   # ENDT ids (+0x0c..+0x14)
    boss = property(lambda s: s.raw[11])             # BOSS id   (+0x16)
    pop_velocity = property(lambda s: s.raw[16])     # +0x20 bump/pop impulse
    gravity = property(lambda s: s.raw[23])          # +0x2e per-tick vy gain
    friction = property(lambda s: s.raw[24])         # +0x30 per-tick vx decay
    jump_velocity = property(lambda s: s.raw[27])    # +0x36 player jump
    max_walk = property(lambda s: s.raw[28])         # +0x38
    walk_accel = property(lambda s: s.raw[29])       # +0x3a
    hint_strings = property(lambda s: s.raw[31:37])  # RT_STRING ids


# Enemy type ids as compared in 0x41367c / 0x40c01b. Names come from the
# string list in Bonkheads.exe; the pairing is inferred from the order in
# which each type first appears versus the level hint strings.
ENEMY_KINDS = {7: "bulldog", 15: "raccoon", 23: "killer bee", 56: "spider",
               27: "baby raptor (inferred)", 52: "king cobra (inferred)",
               19: "chaser (unnamed)", 11: "mystery gem (pickup)"}


# Original tile codes -> this rebuild's level characters (docs/making-levels.md).
# Codes without an equivalent fall back to the closest playable tile.
TILE_TO_CHAR = {0: ".", 1: "-", 2: "=", 3: "#", 4: "~", 5: "^", 6: "!", 7: "#", 8: "-",
                9: "*", 24: ".", 25: "*", 26: "#", 65535: "."}
TILE_TO_CHAR.update({c: "g" for c in (*range(11, 24), 27, 28)})   # bricks holding items

# Original pest type id -> rebuild PestKind name.
KIND_NAMES = {7: "bulldog", 15: "raccoon", 23: "bee", 56: "spider", 27: "raptor", 52: "cobra", 19: "cobra"}


def load_all(levels_exe: PEImage) -> dict[str, dict]:
    """Every level resource, decoded, keyed by resource type."""
    return {
        "maps": {k: TileMap.parse(v) for k, v in levels_exe.resources_of("BKMP").items()},
        "spawns": {k: parse_spawns(v) for k, v in levels_exe.resources_of("ENDT").items()},
        "worlds": {k: World.parse(v) for k, v in levels_exe.resources_of("MLST").items()},
        "bosses": {k: struct.unpack("<15h", v) for k, v in levels_exe.resources_of("BOSS").items()},
    }
