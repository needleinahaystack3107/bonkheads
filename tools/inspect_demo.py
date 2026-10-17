#!/usr/bin/env python3 -I
"""Read-only inspector for the user's original Bonkheads demo files.

Every subcommand goes through bonklib, so formats are parsed in one place.
Nothing here executes the original binaries.

  python3 -I tools/inspect_demo.py resources Levels.exe
  python3 -I tools/inspect_demo.py map 1          # ASCII tile grid of BKMP #1
  python3 -I tools/inspect_demo.py spawns 2       # ENDT #2 records
  python3 -I tools/inspect_demo.py worlds         # MLST physics table
  python3 -I tools/inspect_demo.py hints          # RT_STRING level hints
  python3 -I tools/inspect_demo.py sprite 129     # SPRT #129 as ASCII
"""
import argparse
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bonklib import demo_file, levels, pe, sprites  # noqa: E402


def cmd_resources(args):
    img = pe.PEImage(demo_file(args.file))
    counts = Counter(r.type_label for r in img.resources())
    for label, n in sorted(counts.items()):
        print(f"{label:12} {n}")


def cmd_map(args):
    data = levels.load_all(pe.PEImage(demo_file("Levels.exe")))
    for row in data["maps"][args.id].rows():
        print("".join("." if t == 0 else chr(48 + t % 75) for t in row))


def cmd_spawns(args):
    data = levels.load_all(pe.PEImage(demo_file("Levels.exe")))
    for s in data["spawns"][args.id]:
        print(levels.ENEMY_KINDS.get(s.kind, s.kind), s)


def cmd_worlds(_args):
    data = levels.load_all(pe.PEImage(demo_file("Levels.exe")))
    print("id     grav fric jump maxwalk accel pop  maps")
    for wid, w in sorted(data["worlds"].items()):
        print(f"{wid:<6} {w.gravity:<4} {w.friction:<4} {w.jump_velocity:<4} "
              f"{w.max_walk:<7} {w.walk_accel:<5} {w.pop_velocity:<4} {w.maps}")


def cmd_hints(_args):
    for sid, text in sorted(pe.string_table(pe.PEImage(demo_file("Levels.exe"))).items()):
        print(sid, text)


def cmd_sprite(args):
    img = pe.PEImage(demo_file("Data.exe"))
    s = sprites.decode(img.resources_of("SPRT")[args.id])
    print(s.size)
    for row in s.pixels:
        print("".join(" " if v is None else "#" for v in row))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(required=True)
    sub.add_parser("resources").add_argument("file")
    for name in ("map", "spawns", "sprite"):
        sub.add_parser(name).add_argument("id", type=int)
    sub.add_parser("worlds")
    sub.add_parser("hints")
    args = p.parse_args()
    {"resources": cmd_resources, "map": cmd_map, "spawns": cmd_spawns, "worlds": cmd_worlds,
     "hints": cmd_hints, "sprite": cmd_sprite}[sys.argv[1]](args)


if __name__ == "__main__":
    main()
