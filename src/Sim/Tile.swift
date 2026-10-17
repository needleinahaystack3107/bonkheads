/// Tiles as written in level files (one character each, see docs/making-levels.md).
enum Tile: Character, CaseIterable {
    case empty = "."
    case brick = "#"        // solid, can be bonked from below
    case floor = "="        // solid ground, cannot be bonked
    case ledge = "-"        // one-way: players stand on it, pests fall through
    case block = "X"        // "unbonkable" solid block
    case ice = "*"          // bonkable and slippery (no friction)
    case quicksand = "~"    // solid, slows walking
    case spring = "^"       // launches whoever lands on it
    case superSpring = "!"  // launches twice as hard
    case gem = "g"          // brick hiding a gem; becomes a brick when bonked

    /// Solid for walking/landing. Pests ignore ledges, as in the original
    /// (they treat only tile codes >= 2 as solid).
    func isSolid(forPlayer: Bool) -> Bool {
        switch self {
        case .empty: return false
        case .ledge: return forPlayer
        default: return true
        }
    }

    /// Stops an upward jump (ledges are one-way, so they don't).
    var blocksHead: Bool { self != .empty && self != .ledge }

    var isBonkable: Bool { self == .brick || self == .ice || self == .gem }
    var isSlippery: Bool { self == .ice }
}
