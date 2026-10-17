/// Per-level "underworld" physics, in the original units (1/16 px per update).
/// The defaults are the values used by most original worlds; the presets
/// mirror the underwater and ice worlds (findings.md, "Player physics").
struct Physics: Equatable {
    var gravity = 15     // added to vy each update while airborne
    var friction = 8     // removed from |vx| each update with no direction held
    var jump = 236       // player jump impulse
    var maxWalk = 96     // player top speed
    var accel = 24       // player acceleration per update
    var pop = 160        // impulse when something is bonked upward
    var maxFall = 240    // terminal falling speed

    static let normal = Physics()
    static let underwater = Physics(gravity: 4, friction: 2, jump: 145, maxWalk: 96, accel: 12, pop: 80)
    static let ice = Physics(gravity: 15, friction: 2, jump: 236, maxWalk: 96, accel: 9, pop: 160)

    static let presets: [String: Physics] = ["normal": .normal, "underwater": .underwater, "ice": .ice]
}
