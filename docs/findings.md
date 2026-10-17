# Bonkheads Demo v1.2.0: static analysis findings

Target: `original-demo/Bonkheads.exe` (PE32 x86, SHA-256 `626c9505…51e0f`) plus the
resource DLLs `Levels.exe` and `Data.exe`. **Nothing was executed.** Everything here
comes from REA 6.5.0 with the Ghidra 12.1.4 provider, plus the read-only parsers in
`tools/bonklib/`.

Function names like `FUN_0040c01b` are Ghidra's labels; the PDB was not shipped. Each
finding is written once, here. Other docs link to the section heading.

Legend: **[obs]** directly observed in decompiled code or bytes · **[inf]** inference ·
**[?]** unknown.

REA evidence: binary overview `ev_3dd4ac4f…cb32`; decompilation batch 1 (0x401000–0x41fe81)
`ev_fe50b273…8c58`; batch 2 (0x4200ec–0x426fcd) `ev_bad53cc1…b8be`; Levels.exe
resource tree `ev_3ae72713…60f7`.

---

## Units and screen

- 640×480, 8-bit palettised DirectDraw surfaces: `FUN_00407734` calls DirectDraw `SetDisplayMode(0x280,0x1e0,8)` and creates three 640×480 surfaces. **[obs]**
- Entity positions (`+0x148` x, `+0x14c` y) and velocities (`+0x140` vx, `+0x144` vy) are
  ints in **1/16 pixel**; the game uses `>> 4` everywhere to get pixels. **[obs]**
- The playfield is a grid of **20 columns × 30 rows of 32×16 px tiles**. Tiles are looked up as
  `grid[col*0x8c + row*4]` (35-int column stride, 30 used). **[obs]** `0x40c01b`, `0x40e9cc`

## Game loop and timing

- `FUN_00401112(n)` busy-waits until `last + n*17 ms` (`GetTickCount`), pumping Win32
  messages, so **one tick = 17 ms ≈ 58.8 Hz**. **[obs]**
- Gameplay calls it with `n=2` (`FUN_0041f619`, and the main play loop around decomp line
  15058), so simulation and rendering run **once per 34 ms ≈ 29.4 updates/s**. All
  per-tick constants below are per *update*. **[obs]** `0x41f619`
- Each update: player 1 update, player 2 update, every pest update, then draw passes
  (`FUN_004258dc`, `FUN_00425ab4`, `FUN_00425db3`, `FUN_00425bc5`), then wait, then input
  poll. **[obs/inf]**

## Input and 2-player controls

- `FUN_004093b2` (default prefs) and `FUN_004020cf` (prefs → input struct) give the
  defaults, all polled with `GetAsyncKeyState` in `FUN_004014cc`: **[obs]**

  | | Right | Left | Jump |
  |---|---|---|---|
  | Player 1 | → (VK 0x27) | ← (0x25) | ↑ (0x26) |
  | Player 2 | D (0x44) | A (0x41) | S (0x53) |

- Extra keys at input slots 0x0d–0x17: Ctrl, Q, Esc, F12, Shift and `` ` ``
  (menu/pause/quit). **[obs]** Exactly which does which is **[?]**.
- Each player can use a DirectInput joystick instead, with the three actions mapped to
  axes or buttons (`FUN_00406e06`). **[obs]**
- Jump is edge-triggered: a latch (`DAT_004362ef` for P1) must be re-armed by releasing
  the key. Holding jump does not bunny-hop. **[obs]** `0x40e9cc`
- Cheat words typed via `WM_CHAR` (`FUN_004011e8`): `1amfast`, `1amslow`, `1amskip`,
  `1ambrother`, `1amfretrol`, `1amtnt`. **[obs]**

## Player physics (`FUN_0040e9cc` P1, `FUN_0040fce8` P2: duplicated code)

All constants come from the current world's MLST record (see [Original resource formats](#original-resource-formats)).

- **Walk:** while a direction is held, `vx += accel` (MLST `+0x3a`) up to `±maxWalk`
  (`+0x38`). Holding both? Left wins: the "left" branch is checked first. **[obs]**
- **Friction:** with no direction held, `|vx|` falls by `friction` (`+0x30`) per update,
  clamped at 0. Tile 25 (`0x19`) disables friction (ice). **[obs]**
- **Gravity:** in the air, `vy += gravity` (`+0x2e`) while `vy < 240` (terminal speed
  15 px/update). **[obs]**
- **Jump:** only when grounded: `y -= 1px; vy = -jumpVelocity` (`+0x36`). **[obs]**
- Typical world: accel 24, max 96 (6 px/update), friction 8, gravity 15, jump 236,
  which gives an apex of about 116 px ≈ 7 tile rows, the exact spacing of the platform
  tiers. Underwater worlds 130/140: gravity 4, jump 145, accel 12, friction 2, pop 80.
  Ice worlds 132/148: friction 2, accel 9. **[obs]** (`tools/inspect_demo.py worlds`)
- **Head-bonk:** moving up into a solid tile stops `vy`, snaps to the tile and
  triggers a tile bump (next section). **[obs]**
- **Landing** on a bumped tile (bump timer > 998) bounces the player with `-pop`. **[obs]**
- Springs: tile 5 gives `vy = -(2*pop - 50)` (or `-(2*pop - 30)` if you jumped onto it),
  tile 6 (super-spring) gives `vy = -2*pop`. **[obs]**

## The bonk-from-below, then kick mechanic

1. **Bump:** `FUN_004160ce` runs when a player's head hits a tile. It spawns a short tile
   animation (`FUN_00416c46`, vy −0x60 then +0x60 over 6 frames) and writes a **bump
   timer** into a parallel grid (`+0xdac`): 999 for P1, 1000 for P2, 1001 for chain
   bumps. The values attribute score. Bumping also chains to the tile directly above.
   Item tiles 11–23 and 27–28 release their pickup and turn into plain brick (3). **[obs]**
2. **Flip:** every pest checks the tile under its feet (`FUN_0040c01b`). If that tile's
   bump timer is > 998 the pest is **flipped** (`+0xf3 = 1`), popped up with
   `vy = -pop`, and nudged ±0x40 away from the bump centre. Bumping an already-flipped
   pest *rights* it. **[obs]**
3. **Recover:** a flipped pest counts up `+0x116` toward its stun length `+0x118`. At
   half-time it starts to shake. At full time it gets up as its "angry" variant
   (`type+1` animation, faster). **[obs]** The exact speed-up is **[inf]**.
4. **Kick:** in `FUN_00412074`, if a player overlaps a flipped pest (the hitboxes are inset
   5 px from the pest's edges and 10/5 px from the player's), the pest gets
   `dead = 1`, `vy = -pop`, and `vx` = the kicking player's `vx`. It flies off screen,
   is removed once `y > 500`, and the player scores the ENDT `points`. **[obs]**
5. **Death:** touching an *upright* pest kills the player (`FUN_0040e496`). The pest
   hops (`vy = -48`). **[obs]**
6. A level is cleared when every scheduled pest has been kicked. **[inf]**, consistent
   with the hint text.

## Screen-edge wraparound and pipes

- **Players:** x < −24 px wraps to x = 616; x > 616 wraps to −24. If the row at the
  far edge is a solid column (tile ≥ 2), the player is pushed back instead (vx ±0x18).
  **[obs]** `0x40e9cc`
- **Pests above y = 303 px** wrap the same way (to 639 / −20). **[obs]**
- **Pests below y = 303 px** (the bottom floor) walking off an edge **re-enter at their
  spawn pipe** at the top (`+0x128/+0x12c`) and turn around. This is the classic
  Mario Bros. recycling. **[obs]** `0x40c01b`

## Pest types and AI

Type IDs as compared in `FUN_0041367c` and `FUN_0040c01b`. Names come from the
exe's string list; the type↔name pairing is **[inf]** from the order in which each
type first appears next to the level hint strings.

| id | name | first map | behaviour seen in the code |
|---|---|---|---|
| 7 | Bulldog | 1 | plain walker at its ENDT speed **[obs]** |
| 15 | Raccoon | 2 | plain walker, higher speed (vx 25 vs 15) **[obs]** |
| 23 | Killer Bee | 5 | hops; can only be flipped while landed (hint 5) **[inf]** |
| 56 | Spider | 8 | spawns from mid-screen at the top (x 288–320) **[obs]** |
| 27 | Baby Raptor? | 19 | speed oscillates on a 40-step table (`DAT_004361f8`) **[obs]** |
| 52 | King Cobra? | 37 | fast **[inf]** |
| 19 | (chaser) | 57 | steers toward a player within 80 px below it **[obs]** |
| 11 | Mystery Gem | – | pickup: collected on touch, bonus **[obs]** |

Bosses: one BOSS record per world, read by `FUN_004182c4`. Field 1 selects the
boss: 1 = Shrew Man-Chew, 2 = T. Wrecks, 3 = D. Evil. The update hook is
`FUN_00419196`, `FUN_0041a0be` or `FUN_0041c70e` respectively. **[obs]**

**T. Wrecks** (`FUN_0041a0be`, level 30 = BKMP 30, world 132, BOSS 5):
- He is three entities (head, body, tail) drawn from sprites 3500–3573. **[obs]**
- He spans five tile columns. A bump under any of them makes him hop
  (`vy = -128`) and counts a hit, and each hit scores `10000 / hits` for the
  bumping player. At `BOSS[4]` hits (4 on level 30) he is knocked out. **[obs]**
- He runs at `BOSS[6]` (90) and does not wrap. Once x leaves −250…800 px he waits
  a random 30–80 updates, then `FUN_0041a956` re-enters him on a tier that
  has floor at the screen edge. **[obs]**
- The "full fury" long jumps come from hint 141 **[inf]**. The exact jump logic in
  `FUN_0041ae35` was not traced **[?]**.

Shrew's spin attack and D. Evil's fireballs were not analysed **[?]**.

Difficulty (`FUN_0042209c`): Easy keeps 1/3 of the spawns and scales the speeds by 3/4; Hard
scales them by 4/3. **[obs]**

## Tile codes (BKMP)

| code | meaning | evidence |
|---|---|---|
| 0 | empty | |
| 1 | player-only ledge (pests fall through; pests treat solid as ≥ 2) | `0x40c01b` vs `0x40e9cc` **[obs]** |
| 2 | floor (bottom 4 rows) | **[obs]** |
| 3 | brick (bumpable) | **[obs]** |
| 4 | quicksand (slows) | flag `+0xf9` **[obs]** |
| 5 / 6 | spring / super-spring | **[obs]** |
| 7 | sticky (cancels vy) | **[obs]** |
| 8 | web (breaks on hard landing) | `FUN_00415c46` **[obs]** |
| 9 | hologram/ice block **[?]** | |
| 11–23, 27–28 | brick holding a mineral/item (includes 14 and 20, which sit at the platform ends) | `FUN_004160ce` **[obs]** |
| 24 | hazard (kills) | **[obs]** |
| 25 | ice (no friction) | **[obs]** |
| 26 | TNT-style bump-on-land **[inf]** | |
| 50 / 51 | player 1 / player 2 start | **[inf]** |
| 65535 | unused sentinel **[?]** | |

## Original resource formats

Parsed by `tools/bonklib/levels.py`, `sprites.py` and `pe.py`; run `tools/inspect_demo.py`
to look at them.

- **Levels.exe**: 145 `BKMP`, 131 `ENDT`, 31 `MLST`, 29 `BOSS` and 144 hint strings.
  - `BKMP` (1200 B): 600 × uint16 tile codes, **column-major** (`x*30+y`), 20×30.
  - `ENDT`: int16 count, then count × 13 int16 records: kind, speed, ?, vx (sign picks
    the pipe), ?, ?, ?, points, delay, left_x, right_x, left_y, right_y.
  - `MLST` (80 B = 40 int16): one *underworld*. Fields: 5 BKMP IDs, music/background
    (900+), 5 ENDT IDs (+0x0c), BOSS ID (+0x16), then the physics: pop +0x20, gravity
    +0x2e, friction +0x30, jump +0x36, maxWalk +0x38, accel +0x3a, and 6 hint string
    IDs. The game reads the world as `level/6 + 128`; slot `level % 6 == 5` is the boss
    stage (`FUN_0041e3ec`). **[obs]**
  - `BOSS` (30 B): 15 int16 boss parameters **[?]**.
- **Data.exe**: 479 `SPRT`, 37 `WAV`, 1 `PALETTE` (256×RGB), 4 `APLY`.
  - `SPRT`: int16 rect (l, t, r, b), then u32 records with op = high byte: 1 = new
    row, 3 = skip *n* transparent pixels, 2 = *n* literal palette bytes padded to 4.
    Most actors are 48×48 frames. **[obs]** Decoded and checked as ASCII art.

## Original sprites (for local play)

Identified from contact sheets made with `bonklib.sprites.contact_sheet`. Each
walk cycle is 8 frames, facing right and then left, and the pests also have
"kicked" (spinning) and "stunned" (on its back) sets:

| actor | right | left | kicked | stunned |
|---|---|---|---|---|
| Grag (P1, green troll) | 800–807 | 820–827 | hit: 928 | |
| Thog (P2, teal troll) | 900–907 | 920–927 | hit: 929 | |
| Bulldog | 750–757 | 758–765 | 770–777 | 780–787 |
| Raccoon | 1100–1107 | 1108–1115 | 1120–1127 | 1130–1137 |
| Killer Bee | 1205–1212 | 1213–1220 | 1221–1228 | 1229–1236 |
| King Cobra | 1250–1257 | 1258–1265 | 1266–1273 | 1274–1281 |
| Baby Raptor | 4000–4007 | 4010–4017 | 4020–4027 | 4030–4037 |
| Spider | 4040–4047 | 4050–4057 | 4060–4067 | 4070–4077 |
| Shrew Man-Chew | 3000–3007 | 3008–3015 | | 3016–3023 |

Other ranges: 128–139 springs (tyres), 1300–1302 TNT, 1350–1379 digits,
2000–2910 minerals and webs, and 7001 the troll portrait.

T. Wrecks' head, body and tail offsets are approximate: frames 3500 and 3512
are placed relative to the feet. **[inf]**

`tools/export_original.py` writes these frames, plus level 30 as a level file,
into git-ignored folders. They are for playing on your own machine only.

## Sound and music

- `Data.exe` holds 37 `WAV` resources (8-bit mono, 22,050 Hz). WAV **10000** (23 s)
  is loaded at startup by `FUN_0040a0ce` and looped as the music. **[obs]**
- Effects play by index through `FUN_0040245b` → `FUN_0040a20c`. The index → WAV id
  table is filled in one function by repeated `FUN_00402442(index, id)` calls,
  e.g. 0x0c → 270 (brick bump), 0x13 → 310 (player hit), 0x15/0x16 → 600/610 (springs),
  0x2a → 361 (T. Wrecks hit). **[obs]**
- Each creature yelps differently when kicked (`FUN_00412987` switches on its type):
  bulldog 215, raccoon 200, bee 225, spider 451, raptor 453, cobra 450. **[obs]**
- The 4 `APLY` resources are recorded inputs for the "Bonkheads' Autoplay"
  attract mode, not audio. **[inf]**

`tools/export_original.py` copies these WAVs, for local play only.

## Language choices

- **Analysis tooling: Python 3** (stdlib only, macOS's `/usr/bin/python3`). Formats
  change while you're still learning them, and Python lets the parsers be edited
  alongside Ghidra output. It needs no installs and no build step.
- **Game: Swift 6 + SpriteKit** (arm64, built with SwiftPM from the Command Line
  Tools already on this Mac). SpriteKit is Apple's GPU (Metal) 2D engine, with
  smooth vsync'd rendering, particles, actions and lighting. That covers the
  "Unity-like" polish requested without adding SDL, Rust or Xcode. Codable gives the
  JSON level format for free. The simulation itself is plain Swift structs on a fixed
  tick, so the feel matches the original no matter the frame rate.

## Open questions

Boss AI, the exact angry-variant speeds, tiles 9/14/20/26/65535, the extra-key roles,
and the bee's flight pattern were not fully traced. The rebuild treats them as design
choices.
