/// The 20x30 playfield. Columns wrap around (the world is a cylinder, like the
/// original's screen-edge wraparound); rows outside the grid are empty air.
struct TileGrid {
    private var tiles: [Tile]   // row-major

    init(rows: [[Tile]]) {
        precondition(rows.count == Units.rows && rows.allSatisfy { $0.count == Units.cols })
        tiles = rows.flatMap { $0 }
    }

    func wrapCol(_ col: Int) -> Int { ((col % Units.cols) + Units.cols) % Units.cols }

    subscript(col: Int, row: Int) -> Tile {
        get {
            guard (0..<Units.rows).contains(row) else { return .empty }
            return tiles[row * Units.cols + wrapCol(col)]
        }
        set {
            guard (0..<Units.rows).contains(row) else { return }
            tiles[row * Units.cols + wrapCol(col)] = newValue
        }
    }

    /// First matching tile on `row` between two pixel x positions.
    func firstTile(row: Int, from x0: Int, to x1: Int, where match: (Tile) -> Bool) -> (col: Int, tile: Tile)? {
        for col in floorDiv(x0, Units.tileW)...floorDiv(x1, Units.tileW) where match(self[col, row]) {
            return (wrapCol(col), self[col, row])
        }
        return nil
    }

    /// First matching tile in `col` between two pixel y positions.
    func firstTile(col: Int, from y0: Int, to y1: Int, where match: (Tile) -> Bool) -> (row: Int, tile: Tile)? {
        guard y1 >= y0 else { return nil }
        for row in floorDiv(y0, Units.tileH)...floorDiv(y1, Units.tileH) where match(self[col, row]) {
            return (row, self[col, row])
        }
        return nil
    }
}

/// Integer division rounding toward negative infinity (pixels left of the screen).
func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
