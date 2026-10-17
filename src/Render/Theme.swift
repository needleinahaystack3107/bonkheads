import AppKit

/// Visual mood of a level. Chosen in the level file ("theme"), or picked from
/// the physics preset when omitted (underwater levels look underwater).
@MainActor
enum Theme: String, CaseIterable {
    case cave, underwater, ice, lava, meadow

    static func resolve(_ name: String?, physics: Physics) -> Theme {
        if let name, let t = Theme(rawValue: name) { return t }
        switch physics {
        case .underwater: return .underwater
        case .ice: return .ice
        default: return .cave
        }
    }

    var skyTop: UInt32 {
        switch self { case .cave: 0x1B2A4A; case .underwater: 0x0B3B66; case .ice: 0x9FD3F0; case .lava: 0x2A0A12; case .meadow: 0x7EC8F2 }
    }
    var skyBottom: UInt32 {
        switch self { case .cave: 0x3A1E3F; case .underwater: 0x0E6E8C; case .ice: 0xE6F5FF; case .lava: 0x7A1E10; case .meadow: 0xD8F0C8 }
    }
    var ambientColor: NSColor {
        switch self {
        case .cave: Art.color(0xC9B8FF); case .underwater: Art.color(0xCFF6FF); case .ice: .white
        case .lava: Art.color(0xFF9A3C); case .meadow: Art.color(0xFFF6A8)
        }
    }
    var ambientRisesUp: Bool { self == .underwater || self == .lava }
    var ambientSpeed: CGFloat { self == .ice ? 40 : 22 }
    var ambientRate: CGFloat { self == .ice ? 7 : 3 }
}
