/// A moving box in the tile world. Players, pests and gems all share this
/// one implementation of gravity, tile collision and screen wraparound.
struct Body {
    var x = 0, y = 0          // top-left, sub-pixels
    var vx = 0, vy = 0        // sub-pixels per update
    let w: Int, h: Int        // pixels
    var grounded = false
    var prevX = 0, prevY = 0  // previous update, for render interpolation

    init(w: Int, h: Int, x: Int = 0, y: Int = 0) {
        self.w = w; self.h = h; self.x = x; self.y = y
        prevX = x; prevY = y
    }

    var left: Int { x.px }
    var top: Int { y.px }
    var right: Int { x.px + w }
    var bottom: Int { y.px + h }
    var centerX: Int { x.px + w / 2 }
    /// Feet are sampled slightly inside the box so you can drop through
    /// gaps exactly one body-width wide (the original insets by 5-12 px).
    var footLeft: Int { left + w / 4 }
    var footRight: Int { right - w / 4 - 1 }

    func overlaps(_ o: Body, inset: Int = 0) -> Bool {
        left + inset < o.right - inset && o.left + inset < right - inset &&
            top + inset < o.bottom - inset && o.top + inset < bottom - inset
    }
}

/// What happened while moving a body this update.
struct MoveResult {
    var landedOn: (col: Int, row: Int, tile: Tile)?
    var bonkedHead: (col: Int, row: Int)?
    var hitWall = false
}

extension Body {
    mutating func applyGravity(_ physics: Physics) {
        if (!grounded || vy < 0) && vy < physics.maxFall { vy += physics.gravity }
    }

    /// Moves one update against the tile grid and wraps at the screen edges.
    /// `isPlayer` selects ledge solidity; `wraps` is false for actors that
    /// leave the screen instead (T. Wrecks).
    mutating func move(in grid: TileGrid, isPlayer: Bool, wraps: Bool = true) -> MoveResult {
        var result = MoveResult()
        prevX = x; prevY = y

        // Vertical first: landing and head-bonks are what the game is about.
        let oldBottom = bottom
        y += vy
        if vy > 0 {
            let row = Swift.max(bottom - 1, 0) / Units.tileH
            if let hit = grid.firstTile(row: row, from: footLeft, to: footRight,
                                        where: { $0.isSolid(forPlayer: isPlayer) }),
               oldBottom <= row * Units.tileH {
                y = (row * Units.tileH - h).sub
                vy = 0
                result.landedOn = (hit.col, row, hit.tile)
            }
        } else if vy < 0, top >= 0 {
            let row = top / Units.tileH
            // Prefer the tile under the head's centre, as the original does.
            let centre = grid.wrapCol(centerX / Units.tileW)
            let hit = grid[centre, row].blocksHead ? (col: centre, tile: grid[centre, row])
                : grid.firstTile(row: row, from: left + 3, to: right - 4, where: { $0.blocksHead })
            if let hit {
                y = ((row + 1) * Units.tileH).sub
                vy = 0
                result.bonkedHead = (hit.col, row)
            }
        }

        // Horizontal: bounce off solid walls (the original negates vx).
        x += vx
        if vx != 0 {
            let edge = vx > 0 ? right - 1 : left
            if grid.firstTile(col: grid.wrapCol(floorDiv(edge, Units.tileW)),
                              from: top + 2, to: bottom - 3,
                              where: { $0.isSolid(forPlayer: false) && $0 != .ledge }) != nil {
                x -= vx
                vx = -vx
                result.hitWall = true
            }
        }

        if wraps { wrapHorizontally() }
        grounded = isSupported(in: grid, isPlayer: isPlayer)
        return result
    }

    mutating func wrapHorizontally() {
        if left + w / 2 < 0 { x += Units.screenW.sub; prevX += Units.screenW.sub }
        if left + w / 2 >= Units.screenW { x -= Units.screenW.sub; prevX -= Units.screenW.sub }
    }

    func isSupported(in grid: TileGrid, isPlayer: Bool) -> Bool {
        guard bottom % Units.tileH == 0, vy >= 0 else { return false }
        return grid.firstTile(row: bottom / Units.tileH, from: footLeft, to: footRight,
                              where: { $0.isSolid(forPlayer: isPlayer) }) != nil
    }

    /// The tile directly under the feet centre, if standing.
    func tileUnderFeet(in grid: TileGrid) -> (col: Int, row: Int, tile: Tile)? {
        guard grounded else { return nil }
        let row = bottom / Units.tileH
        if let hit = grid.firstTile(row: row, from: footLeft, to: footRight, where: { $0 != .empty }) {
            return (hit.col, row, hit.tile)
        }
        return nil
    }
}
