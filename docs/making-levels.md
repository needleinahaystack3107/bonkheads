# Making your own levels

Every `.json` file in `levels/` is a level. The game plays them in filename
order (`01-…`, `02-…`), so the number prefix sets the order. Add a file and
restart the game to play it.

Check your level before playing:

```bash
.build/release/Bonkheads --validate levels/my-level.json
```

With no file names, `--validate` checks the whole `levels/` folder. It points
to the exact row and column of any mistake.

## A complete example

```json
{
  "name": "My First Level",
  "author": "you",
  "hint": "Shown under the level name when it starts.",
  "theme": "meadow",
  "physics": "normal",
  "tiles": [
    "....................",
    "....................",
    "....................",
    "....................",
    "....................",
    "######........######",
    "....................",
    "....................",
    "....................",
    "....................",
    "....................",
    "....................",
    "####....#gg#....####",
    "....................",
    "....................",
    "....................",
    "....................",
    "....................",
    "....................",
    "#####...####...#####",
    "....................",
    "....................",
    "....................",
    "....................",
    "....................",
    ".....1........2.....",
    "^==================^",
    "====================",
    "====================",
    "===================="
  ],
  "pests": [
    { "kind": "bulldog", "at": 1 },
    { "kind": "raccoon", "at": 5, "from": "right" },
    { "kind": "bee", "at": 9, "speed": 30 }
  ],
  "boss": { "kind": "shrew", "hits": 3, "at": 20 }
}
```

## The tile grid

`tiles` is the screen: **30 rows of exactly 20 characters**. Each character is
one 32×16-pixel block, which makes the screen 640×480.

| char | tile | notes |
|---|---|---|
| `.` | empty | |
| `#` | brick | bonk it from below to flip the pests standing on it |
| `=` | floor | solid, can't be bonked; usually the bottom 4 rows |
| `-` | ledge | players can stand on it, pests fall through, you can jump up through it |
| `X` | metal block | solid, can't be bonked |
| `*` | ice brick | bonkable and slippery (no friction) |
| `~` | quicksand | solid, but you walk at 1/3 speed and jump lower |
| `^` | spring | bounces whoever lands on it |
| `!` | super spring | bounces twice as hard |
| `g` | gem brick | bonk it to release a gem worth 500 points |
| `1` `2` | player starts | put one in the empty row just above a floor; `2` is optional |

Tips, all inherited from the original game's design:

- A normal jump rises about 7 rows (116 px), so put tiers **7 rows apart**
  (rows 5, 12, 19, then the floor at 26). That way every tier can be bonked
  from the one below.
- Leave **gaps at least 3 tiles wide** so players can jump up between tiers.
- The left and right edges wrap around. A pest on the bottom floor that walks
  off an edge goes back up to its pipe.

## Pests

Each entry in `pests` makes one pest appear at `at` seconds after the level
starts.

| kind | behaviour | points |
|---|---|---|
| `bulldog` | walks steadily | 100 |
| `raccoon` | walks faster | 150 |
| `bee` | hops; you can only flip it while it's landed | 250 |
| `spider` | drops in from the top pipe | 350 |
| `raptor` | speed surges back and forth | 400 |
| `cobra` | darts toward a nearby player | 400 |

Optional fields:

- `"from"`: `"left"`, `"right"` or `"top"`. By default pests alternate left and right.
- `"speed"`: walking speed in the original units (1/16 px per update). Bulldogs
  use 15, raccoons 25, and 1–200 is allowed.

A pest that recovers from being flipped gets angry, which means faster and
worth more points. Kick it before that happens.

## Boss (optional)

```json
"boss": { "kind": "shrew", "hits": 3, "at": 20 }
```

- `"shrew"`: hops around and leaps at players. Bonk it `hits` times, then kick it.
- `"rex"`: T. Wrecks. He charges across a tier, runs off screen, and comes back
  on another tier. Every bonk under him scores; `hits` bonks knock him out.

The level is cleared when every pest and the boss have been dealt with.

## Getting tougher (campaign progression)

Levels play in filename order, and each one is a little harder than the one
before. At the Nth level, pests are about 8% faster per step, arrive about
5% sooner and recover from a flip about 6% quicker. These are capped so late
levels stay fair, and the level select shows each level's boost. To play a
level exactly as written, add:

```json
"scaling": false
```

## Pipes (optional)

Where pests appear, as `[column, row]` (0-based). A pest stands on top of the
row below the given cell:

```json
"pipes": { "left": [0, 4], "right": [19, 4], "top": [9, 0] }
```

## Theme and physics (optional)

`"theme"` sets the look: `cave`, `underwater`, `ice`, `lava` or `meadow`.

`"physics"` sets how the world feels. Use a preset name (`"normal"`,
`"underwater"`, `"ice"`) or an object that overrides single values:

```json
"physics": { "preset": "underwater", "jump": 160 }
```

| field | normal | meaning (original units: 1/16 px per update) |
|---|---|---|
| `gravity` | 15 | added to falling speed every update |
| `friction` | 8 | how fast you stop when you let go |
| `jump` | 236 | jump strength |
| `maxWalk` | 96 | top walking speed |
| `accel` | 24 | how quickly you reach top speed |
| `pop` | 160 | how hard a bonk launches things upward |

These are the values the 2003 game used; the presets copy its underwater and
ice worlds (see [findings.md](findings.md#player-physics-fun_0040e9cc-p1-fun_0040fce8-p2-duplicated-code)).

If you leave out `theme`, it follows the physics: underwater physics gets the
underwater look, ice physics the ice look, anything else the cave.
