/// Pest kinds usable in level files. Behaviour is data plus one small
/// `Behavior` switch; every pest shares the same Body physics, flip and kick
/// rules (findings.md, "The bonk-from-below, then kick mechanic").
enum PestKind: String, CaseIterable {
    case bulldog, raccoon, bee, spider, raptor, cobra

    var traits: PestTraits {
        switch self {
        case .bulldog: return PestTraits(speed: 15, points: 100, behavior: .walk)
        case .raccoon: return PestTraits(speed: 25, points: 150, behavior: .walk)
        case .bee:     return PestTraits(speed: 20, points: 250, behavior: .hop)
        case .spider:  return PestTraits(speed: 20, points: 350, behavior: .walk, fromTop: true)
        case .raptor:  return PestTraits(speed: 20, points: 400, behavior: .surge)
        case .cobra:   return PestTraits(speed: 30, points: 400, behavior: .chase)
        }
    }
}

struct PestTraits {
    var speed: Int                 // sub-pixels per update (original ENDT vx)
    var points: Int
    var behavior: Behavior
    var fromTop = false
    var stunTicks = 150            // ~5 s on its back before getting up angry
    var size = (w: 28, h: 26)
}

enum Behavior {
    case walk    // straight ahead, Mario Bros. style
    case hop     // little hops; can only be flipped while landed
    case surge   // speed pulses (original 0x1b speed table)
    case chase   // speeds toward a nearby player on its level (original 0x13)
    case boss    // takes several bonks, leaps at players
    case rex     // T. Wrecks: charges across a tier, off screen, and back (0x41a0be)
}

struct Pest {
    let id: Int
    let kind: PestKind?            // nil for the boss
    var body: Body
    var direction: Int             // -1 or +1
    var speed: Int
    let points: Int
    let behavior: Behavior
    let stunTicks: Int
    let home: PipeSide

    var flipped = false
    var stunTimer = 0
    var anger = 0                  // each recovery makes it faster
    var dead = false               // kicked, falling off screen
    var age = 0
    var hp = 1
    var lastBumpID = -1

    var offscreenTimer = 0         // T. Wrecks: ticks left before re-entering
    var isShaking: Bool { flipped && stunTimer > stunTicks / 2 && hp <= 1 }
    var isDangerous: Bool { !flipped && !dead }
    var effectiveSpeed: Int { behavior == .rex ? speed : speed + speed * anger * 2 / 5 }

    /// Per-behaviour steering, run before the shared physics step.
    mutating func steer(players: [Player], physics: Physics) {
        age += 1
        guard !flipped else {
            if body.grounded { body.vx = 0 }
            return
        }
        var target = direction * effectiveSpeed
        switch behavior {
        case .walk:
            break
        case .hop:
            if body.grounded && age % 45 == 0 { body.vy = -physics.pop * 3 / 4 }
        case .surge:
            // Triangle wave between 0.5x and 2x walking speed.
            let phase = age % 80
            let factor = phase < 40 ? 50 + phase * 150 / 40 : 200 - (phase - 40) * 150 / 40
            target = target * factor / 100
        case .chase:
            if let prey = players.filter({ $0.isAlive && abs($0.body.bottom - body.bottom) < 20 })
                .min(by: { abs($0.body.centerX - body.centerX) < abs($1.body.centerX - body.centerX) }),
               abs(prey.body.centerX - body.centerX) < 160 {
                direction = prey.body.centerX < body.centerX ? -1 : 1
                target = direction * effectiveSpeed * 2
            }
        case .rex:
            // Charges straight on; once badly hurt he also leaps (hint: "in full
            // fury T. Wrecks can jump large distances").
            if hp <= 2 && body.grounded && age % 90 == 0 { body.vy = -physics.jump * 11 / 10 }
            target = direction * effectiveSpeed
        case .boss:
            if body.grounded && age % 110 == 0,
               let prey = players.filter(\.isAlive).randomElement() {
                direction = prey.body.centerX < body.centerX ? -1 : 1
                body.vy = -physics.jump * 9 / 10
                target = direction * effectiveSpeed * 2
            }
        }
        if body.grounded || behavior == .boss || behavior == .hop || behavior == .rex { body.vx = target }
    }

    /// Bonked from below (the tile under its feet was bumped).
    mutating func bonk(from tileCenterX: Int, physics: Physics) {
        body.vy = -physics.pop
        body.grounded = false
        if hp > 1 {                       // boss soaks up hits first
            hp -= 1
            anger += 1
            return
        }
        flipped.toggle()                  // bonking a flipped pest rights it
        stunTimer = 0
        let dx = body.centerX - tileCenterX
        body.vx = abs(dx) > 8 ? (dx > 0 ? 64 : -64) : 0
    }

    /// Counts down the flip; returns true on the update it gets back up.
    mutating func updateStun() -> Bool {
        guard flipped, behavior != .boss else { return false }
        stunTimer += 1
        guard stunTimer >= stunTicks else { return false }
        flipped = false
        anger += 1
        body.vy = -48
        return true
    }

    mutating func kick(by player: Player, physics: Physics) {
        dead = true
        body.vy = -physics.pop
        let away = body.centerX >= player.body.centerX ? 1 : -1
        body.vx = abs(player.body.vx) > 16 ? player.body.vx : away * 64
    }
}
