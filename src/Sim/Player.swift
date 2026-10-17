struct PlayerInput: Equatable {
    var left = false, right = false, jump = false
}

/// A troll. Movement rules follow the original player update
/// (findings.md, "Player physics"); both players share this code.
struct Player {
    enum State: Equatable {
        case alive
        case dying(ticks: Int)     // knocked out, tumbling off screen
        case waiting(ticks: Int)   // about to respawn
        case out                   // no lives left
    }

    let index: Int                 // 0 = player 1, 1 = player 2
    var body = Body(w: 24, h: 40)
    var state = State.alive
    var lives = 3
    var score = 0
    var nextExtraLife = 10_000
    var facing = 1
    var jumpArmed = true           // jump fires on press, not while held
    var invulnerable = 0
    var justJumped = false         // for the renderer's squash & stretch

    var isAlive: Bool { state == .alive }
    var canBeHurt: Bool { isAlive && invulnerable == 0 }

    mutating func place(at cell: Level.Cell) {
        body = Body(w: body.w, h: body.h,
                    x: (cell.col * Units.tileW + (Units.tileW - body.w) / 2).sub,
                    y: ((cell.row + 1) * Units.tileH - body.h).sub)
        state = .alive
        invulnerable = 90
        jumpArmed = false
    }

    mutating func steer(_ input: PlayerInput, physics: Physics, onTile tile: Tile?) {
        justJumped = false
        if invulnerable > 0 { invulnerable -= 1 }
        var maxWalk = physics.maxWalk
        if tile == .quicksand { maxWalk /= 3 }

        // Left is checked first, as in the original.
        if input.left {
            body.vx = body.vx > -maxWalk ? body.vx - physics.accel : -maxWalk
            facing = -1
        } else if input.right {
            body.vx = body.vx < maxWalk ? body.vx + physics.accel : maxWalk
            facing = 1
        } else if tile?.isSlippery != true {
            body.vx = body.vx > 0 ? max(0, body.vx - physics.friction) : min(0, body.vx + physics.friction)
        }
        if abs(body.vx) > maxWalk && body.grounded {
            body.vx = body.vx > 0 ? maxWalk : -maxWalk
        }

        if !input.jump { jumpArmed = true }
        if input.jump && jumpArmed && body.grounded {
            jumpArmed = false
            body.y -= 1.sub
            body.vy = tile == .quicksand ? -physics.jump * 2 / 3 : -physics.jump
            body.grounded = false
            justJumped = true
        }
    }

    mutating func addScore(_ points: Int) -> Bool {
        score += points
        guard score >= nextExtraLife else { return false }
        nextExtraLife += 10_000
        lives += 1
        return true
    }
}
