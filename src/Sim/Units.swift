// Shared measurements. The simulation deliberately keeps the original game's
// integer units (see docs/findings.md, "Units and screen") so the tuned
// constants carry over unchanged and the game feels the same.

enum Units {
    /// Positions and velocities are stored in 1/16 pixel, like the original.
    static let sub = 16

    static let tileW = 32, tileH = 16
    static let cols = 20, rows = 30
    static let screenW = cols * tileW   // 640
    static let screenH = rows * tileH   // 480

    /// One simulation update. The original ran its logic every 2 x 17 ms
    /// (findings.md, "Game loop and timing"); rendering is interpolated in between.
    static let tickSeconds = 0.034

    static func ticks(seconds: Double) -> Int { Int((seconds / tickSeconds).rounded()) }
}

/// Integer pixel <-> sub-pixel helpers, so `>> 4` never appears in game code.
extension Int {
    var px: Int { self >> 4 }            // sub-pixels -> pixels (floor)
    var sub: Int { self * Units.sub }    // pixels -> sub-pixels
}
