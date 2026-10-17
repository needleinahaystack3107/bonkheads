#!/usr/bin/env python3 -I
"""Export original Bonkheads art and the T. Wrecks level for LOCAL play only.

Reads your own copy in original-demo/ and writes:
  local-original/art/*.png + manifest.json   sprites the game uses when present
  levels/original-30-t-wrecks.json            the demo's T. Wrecks boss stage

Both outputs are git-ignored: the originals are copyrighted by 1 A.M.
Productions and must never be committed or shared. Nothing is executed.

  python3 -I tools/export_original.py
"""
import json
import sys
from itertools import accumulate
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bonklib import REPO, demo_file, levels, pe, sprites  # noqa: E402

OUT = REPO / "local-original"

# Sprite IDs per actor and animation (identified from contact sheets of
# Data.exe; see docs/findings.md, "Original sprites"). Each walk cycle is 8 frames.
def run(start, n=8):
    return list(range(start, start + n))

ACTORS = {
    "troll1":  {"right": run(800), "left": run(820), "hit": [928]},
    "troll2":  {"right": run(900), "left": run(920), "hit": [929]},
    "bulldog": {"right": run(750), "left": run(758), "kicked": run(770), "stunned": run(780)},
    "raccoon": {"right": run(1100), "left": run(1108), "kicked": run(1120), "stunned": run(1130)},
    "bee":     {"right": run(1205), "left": run(1213), "kicked": run(1221), "stunned": run(1229)},
    "cobra":   {"right": run(1250), "left": run(1258), "kicked": run(1266), "stunned": run(1274)},
    "raptor":  {"right": run(4000), "left": run(4010), "kicked": run(4020), "stunned": run(4030)},
    "spider":  {"right": run(4040), "left": run(4050), "kicked": run(4060), "stunned": run(4070)},
    "shrew":   {"right": run(3000), "left": run(3008), "stunned": run(3016)},   # Shrew Man-Chew (boss)
}

# Game event -> WAV resource id in Data.exe. The original plays sounds by index
# through a table built in FUN_00418197 (index -> WAV id); the event choice
# comes from the call sites (docs/findings.md, "Sound and music").
SOUNDS = {
    "music": 10000,            # looped from launch (FUN_0040a0ce at startup)
    "bump": 270,               # idx 0x0c, head hits a brick (0x40e9cc)
    "spring": 600, "superSpring": 610,
    "playerHit": 310,          # idx 0x13 (FUN_0040e496)
    "gem": 520,                # idx 0x17 (FUN_00413323)
    "extraLife": 530,          # idx 0x18
    "rexHit": 361,             # idx 0x2a (FUN_0041a0be)
    "levelClear": 800,         # idx 0x35, the longest jingle
    # Kick yelps per creature (FUN_00412987)
    "kick.bulldog": 215, "kick.raccoon": 200, "kick.bee": 225, "kick.spider": 451,
    "kick.raptor": 453, "kick.cobra": 450, "kick.rex": 361, "kick.shrew": 452,
}

# T. Wrecks is drawn as three sprites (body, tail, head). Frames 3500/3512 are
# the full-body walk poses; parts are placed relative to the feet.
REX_FRAMES = [3500, 3512]
REX_SIZE = (130, 110)


def compose(parts, sheet, size):
    w, h = size
    px = [[None] * w for _ in range(h)]
    for sid, x, bottom in parts:
        spr = sprites.decode(sheet[sid])
        sw, sh = spr.size
        for y, row in enumerate(spr.pixels):
            for dx, v in enumerate(row):
                if v is not None and 0 <= x + dx < w and 0 <= bottom - sh + y < h:
                    px[bottom - sh + y][x + dx] = v
    return sprites.Sprite(0, 0, w, h, px)


def mirrored(spr):
    return sprites.Sprite(spr.left, spr.top, spr.right, spr.bottom, [row[::-1] for row in spr.pixels])


def export_art():
    data = pe.PEImage(demo_file("Data.exe"))
    pal = sprites.palette(data.resource("PALETTE", 128))
    sheet = data.resources_of("SPRT")
    art = OUT / "art"
    art.mkdir(parents=True, exist_ok=True)
    manifest = {"actors": {}}

    def save(name, spr):
        sprites.write_png(art / name, *sprites.to_rgba(spr, pal))
        return name

    for actor, anims in ACTORS.items():
        manifest["actors"][actor] = {
            anim: [save(f"{actor}_{anim}_{i}.png", sprites.decode(sheet[sid])) for i, sid in enumerate(ids)]
            for anim, ids in anims.items()
        }
    rex_right = [compose([(f + 2, 12, 72), (f + 1, 26, 108), (f, 64, 68)], sheet, REX_SIZE) for f in REX_FRAMES]
    manifest["actors"]["rex"] = {
        "right": [save(f"rex_right_{i}.png", s) for i, s in enumerate(rex_right)],
        "left": [save(f"rex_left_{i}.png", mirrored(s)) for i, s in enumerate(rex_right)],
    }
    sounds = OUT / "sounds"
    sounds.mkdir(exist_ok=True)
    wavs = data.resources_of("WAV")       # already complete RIFF/WAVE files
    manifest["sounds"] = {}
    for event, wav_id in SOUNDS.items():
        (sounds / f"{wav_id}.wav").write_bytes(wavs[wav_id])
        manifest["sounds"][event] = f"{wav_id}.wav"
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print(f"wrote {sum(len(a) for v in manifest['actors'].values() for a in v.values())} frames to {art}")


def shorten(text, limit=80):
    """Hints are long paragraphs; the banner fits about one line."""
    return text if len(text) <= limit else text[:text.rfind(" ", 0, limit)] + "…"


def export_t_wrecks_level():
    """Level 30: map BKMP 30, world 132 physics, ENDT 25 pests, BOSS 5 (T. Wrecks)."""
    img = pe.PEImage(demo_file("Levels.exe"))
    d = levels.load_all(img)
    world = d["worlds"][132]
    grid = d["maps"][30].rows()
    rows = ["".join(levels.TILE_TO_CHAR.get(t, ".") for t in row) for row in grid]
    rows[25] = ".....1........2....."   # boss stages have no start markers; stand on the floor
    spawns = d["spawns"][world.spawn_tables[0]]
    times = list(accumulate(s.delay for s in spawns))   # delays are gaps between spawns
    boss = d["bosses"][world.boss]
    level = {
        "name": "T. Wrecks (original level 30)",
        "author": "1 A.M. Productions (exported locally, do not share)",
        "hint": shorten(pe.string_table(img)[30]),
        "theme": "ice",
        "physics": {"preset": "normal", "gravity": world.gravity, "friction": world.friction,
                    "jump": world.jump_velocity, "maxWalk": world.max_walk, "accel": world.walk_accel,
                    "pop": world.pop_velocity},
        "tiles": rows,
        # Boss-stage pests drop in from the sky at x=192 / x=480 (ENDT left_x/right_x).
        "pipes": {"left": [spawns[0].left_x // 32, 0], "right": [spawns[0].right_x // 32, 0]},
        "pests": [{"kind": levels.KIND_NAMES[s.kind], "at": round(t * 0.034, 2), "speed": abs(s.vx),
                   "from": "left" if s.vx > 0 else "right"} for s, t in zip(spawns, times)],
        "boss": {"kind": "rex", "hits": boss[4], "at": 0},
        "scaling": False,   # keep it exactly like the original
    }
    out = REPO / "levels" / "original-30-t-wrecks.json"
    out.write_text(json.dumps(level, indent=2))
    print(f"wrote {out}")


if __name__ == "__main__":
    export_art()
    export_t_wrecks_level()
