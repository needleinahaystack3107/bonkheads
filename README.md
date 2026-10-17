# bonkheads (but on my mac)

ok so story time. when i was a little kid at daycare there was this one computer in
the corner and it had **Bonkheads** on it. two trolls, Grag and Thog, bonking pests
from underneath a platform and then kicking them off the screen. you could run off one
side and pop out the other. two people could play at once on the same keyboard, which
meant there was basically always a fight over who got to be player 1.

i hadn't thought about it in years until i heard about
[REA (Reverse Engineer Anything)](https://github.com/morluto/rea) and went "wait...
could i get bonkheads running on my mac??" turns out: yeah, kinda!

## what this actually is

this is **not** the original game. it's a brand new remake written in Swift that copies
how bonkheads *plays*: the jump feel, the bonk-from-below-then-kick thing, the
screen wraparound and the pest behaviour. none of the original code, art or levels are
in this repo.

how i got there:

1. grabbed the official 2003 Bonkheads Demo (v1.2.0) from the old bonkheads.com page on
   the Wayback Machine, checked the hash, and unpacked it **without ever running it**
2. pointed REA + Ghidra at the exe and had Claude dig through the decompiled code to
   work out the physics, the pest AI, the controls and the level format.
   all the notes (with function addresses as receipts) are in
   [`docs/findings.md`](docs/findings.md)
3. rebuilt everything from those notes as a native Apple Silicon app with
   SpriteKit, with my own placeholder art and my own levels

fun stuff the decompiler turned up: player 1 and player 2 each have their **own
copy-pasted physics function** lol, jump only fires on key press (no bunny hopping),
and there are cheat codes like `1amskip` hiding in there.

## play it

needs an Apple Silicon mac with the Xcode command line tools (`xcode-select --install`). no other installs.

```bash
swift build -c release
```

```bash
.build/release/Bonkheads
```

| | left | right | jump |
|---|---|---|---|
| player 1 | ← | → | ↑ |
| player 2 | A | D | S |

same keys as the original. yes, S is jump for player 2. it was like that back then too.

**how to actually win a level** (took me a minute to remember lol): jump into the
platform *under* a pest to flip it onto its back, then run into it while it's flipped to
kick it off the screen. you have about 5 seconds before it gets back up angrier and
faster. kick every pest and the level's done. touching a pest that's standing up costs
a life. first time? pick **How to Play** in the main menu for a guided level.

there's a proper main menu with level select (pick 1 or 2 players with ← →), Esc pauses,
M toggles the music and ⌘Q quits. no double jump btw: you climb mario-bros style, by
jumping up through the gaps between platforms. each level is a bit tougher than the
last (faster pests, quicker spawns).

## make your own levels

this is the part i'm most excited about. every `.json` file in [`levels/`](levels)
is a level: a little text grid of tiles, where the pests spawn, gravity/friction
(ice level!!) and an optional boss. drop a new file in and it shows up in the game.
check it with:

```bash
.build/release/Bonkheads --validate levels/my-level.json
```

full guide: [`docs/making-levels.md`](docs/making-levels.md). there are 3 sample
levels to start from: First Bonk, Ice Cavern and Lava Lair (with a boss).

## where's the original art?

not here, on purpose. Bonkheads belongs to 1 A.M. Productions. if you've got your own
copy of the demo, drop its files in `original-demo/` and run:

```bash
python3 -I tools/export_original.py
```

that pulls the real sprites (Grag, Thog, every pest, Shrew Man-Chew, T. Wrecks), the
original music and sound effects, and the demo's last level, the T. Wrecks fight,
out of your own copy so you can play them locally. all of it lands in git-ignored
folders and never gets uploaded. without it, the game uses my own placeholder art and
is silent.

## repo tour

- `src/Sim/`: the game rules (physics, players, pests, levels). no graphics in here
- `src/Render/`: SpriteKit drawing, effects, themes
- `tools/bonklib/`: little python helpers that read the original demo's file formats
- `tools/inspect_demo.py`, `tools/export_original.py`: research + local-only export
- `docs/`: the reverse-engineering notes + level guide

---

made for fun and nostalgia. all credit for the original game goes to 1 A.M.
Productions. if you ever see this, thank you for my whole childhood 🧌
