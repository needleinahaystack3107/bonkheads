/// Things the renderer may want to show or play. The simulation never draws;
/// it just reports what happened each update.
enum GameEvent {
    case bump(col: Int, row: Int)
    case flip(x: Int, y: Int)
    case kick(x: Int, y: Int, points: Int, player: Int, kind: String)
    case playerHit(player: Int)
    case gem(x: Int, y: Int, player: Int)
    case spring(col: Int, row: Int)
    case extraLife(player: Int)
    case bossHit
    case jump(player: Int)
    case land(player: Int)
    case recover(x: Int, y: Int)     // a flipped pest got back up (angrier)
}

/// A floating gem released from a gem brick. Uses the shared Body physics.
struct Gem {
    let id: Int
    var body: Body
    var life = 400
}

/// One level in progress: players, pests, bumps and spawning.
final class Game {
    let level: Level
    private(set) var grid: TileGrid
    var players: [Player]
    private(set) var pests: [Pest] = []
    private(set) var gems: [Gem] = []
    private(set) var events: [GameEvent] = []
    /// Active tile bumps: animation age per tile (0...bumpTicks).
    private(set) var bumps: [Int: Bump] = [:]
    struct Bump { var age: Int; let id: Int; let player: Int? }
    private(set) var tick = 0

    static let bumpTicks = 6        // the original tile pop lasts 6 frames
    private var nextSpawn = 0
    private var bossSpawned = false
    private var nextID = 1

    var physics: Physics { level.physics }
    var isCleared: Bool {
        nextSpawn == level.spawns.count && (level.boss == nil || bossSpawned) && pests.isEmpty
    }
    /// Pests still to deal with: not yet spawned, plus alive (boss included).
    var pestsLeft: Int {
        (level.spawns.count - nextSpawn) + (level.boss != nil && !bossSpawned ? 1 : 0) + pests.filter { !$0.dead }.count
    }
    var isOver: Bool { players.allSatisfy { $0.state == .out } }

    let difficulty: Difficulty

    init(level: Level, playerCount: Int, carryOver: [Player]? = nil, difficulty: Difficulty = .none) {
        self.level = level
        self.difficulty = level.scales ? difficulty : .none
        grid = level.grid
        players = (0..<playerCount).map { i in
            var p = carryOver?[i] ?? Player(index: i)
            if p.state != .out { p.place(at: level.starts[i]) }
            return p
        }
    }

    static func key(_ col: Int, _ row: Int) -> Int { row * Units.cols + col }

    // MARK: - Update

    func step(inputs: [PlayerInput]) {
        events.removeAll(keepingCapacity: true)
        tick += 1
        spawnDue()
        for i in players.indices { updatePlayer(i, input: i < inputs.count ? inputs[i] : PlayerInput()) }
        for i in pests.indices { updatePest(i) }
        updateGems()
        resolveContacts()
        pests.removeAll { $0.dead && $0.body.top > Units.screenH + 20 }
        bumps = bumps.compactMapValues { b in b.age >= Self.bumpTicks ? nil : Bump(age: b.age + 1, id: b.id, player: b.player) }
    }

    private func spawnDue() {
        while nextSpawn < level.spawns.count, difficulty.spawnTick(level.spawns[nextSpawn].tick) <= tick {
            let s = level.spawns[nextSpawn]
            let t = s.kind.traits
            addPest(kind: s.kind, side: s.side, speed: difficulty.speed(s.speed), points: t.points,
                    behavior: t.behavior, stun: difficulty.stunTicks(t.stunTicks), size: t.size, hp: 1)
            nextSpawn += 1
        }
        if let boss = level.boss, !bossSpawned, tick >= boss.tick {
            bossSpawned = true
            if boss.look == "rex" {
                // BOSS record 5: speed 90, 3500 points, enters from off screen.
                addPest(kind: nil, side: .left, speed: difficulty.speed(90), points: 3500, behavior: .rex,
                        stun: .max, size: (w: 104, h: 60), hp: boss.hits)
                pests[pests.count - 1].offscreenTimer = 40
                pests[pests.count - 1].body.x = (-200).sub
            } else {
                addPest(kind: nil, side: .top, speed: difficulty.speed(22), points: 3000, behavior: .boss,
                        stun: .max, size: (w: 48, h: 44), hp: boss.hits)
            }
        }
    }

    private func addPest(kind: PestKind?, side: PipeSide, speed: Int, points: Int,
                         behavior: Behavior, stun: Int, size: (w: Int, h: Int), hp: Int) {
        let cell = level.pipes[side]!
        let x = min(max(cell.col * Units.tileW + (Units.tileW - size.w) / 2, 0), Units.screenW - size.w)
        let body = Body(w: size.w, h: size.h, x: x.sub, y: ((cell.row + 1) * Units.tileH - size.h).sub)
        let dir = side == .right ? -1 : (side == .left ? 1 : (Bool.random() ? 1 : -1))
        var pest = Pest(id: nextID, kind: kind, body: body, direction: dir, speed: speed, points: points,
                        behavior: behavior, stunTicks: stun, home: side)
        pest.hp = hp
        nextID += 1
        pests.append(pest)
    }

    private func updatePlayer(_ i: Int, input: PlayerInput) {
        var p = players[i]
        switch p.state {
        case .out:
            return
        case .dying(let t):
            p.body.applyGravity(physics)
            p.body.prevX = p.body.x; p.body.prevY = p.body.y
            p.body.y += p.body.vy
            p.state = t > 60 && p.body.top > Units.screenH ? .waiting(ticks: 0) : .dying(ticks: t + 1)
        case .waiting(let t):
            if p.lives <= 0 { p.state = .out }
            else if t > 30 { p.place(at: level.starts[i]) }
            else { p.state = .waiting(ticks: t + 1) }
        case .alive:
            let under = p.body.tileUnderFeet(in: grid)
            p.steer(input, physics: physics, onTile: under?.tile)
            if p.justJumped { events.append(.jump(player: i)) }
            let wasGrounded = p.body.grounded
            // The original adds no gravity on the jump update itself; skipping it
            // here is what lets a jump clear a 7-row tier (~123 px, not ~108).
            if !p.justJumped { p.body.applyGravity(physics) }
            let moved = p.body.move(in: grid, isPlayer: true)
            if let head = moved.bonkedHead { bump(col: head.col, row: head.row, by: i) }
            if let land = moved.landedOn {
                if !wasGrounded { events.append(.land(player: i)) }
                launchIfSpring(&p.body, tile: land.tile, col: land.col, row: land.row)
            }
            // Standing on a tile that is bumped from below pops you up too.
            if activeBump(under: p.body)?.bump.age == 0 {
                p.body.vy = -physics.pop
            }
        }
        players[i] = p
    }

    private func launchIfSpring(_ body: inout Body, tile: Tile, col: Int, row: Int) {
        switch tile {
        case .spring: body.vy = -(physics.pop * 2 - 30)
        case .superSpring: body.vy = -physics.pop * 2
        default: return
        }
        body.grounded = false
        events.append(.spring(col: col, row: row))
    }

    private func updatePest(_ i: Int) {
        var pest = pests[i]
        if pest.dead {
            pest.body.applyGravity(physics)
            pest.body.prevX = pest.body.x; pest.body.prevY = pest.body.y
            pest.body.x += pest.body.vx
            pest.body.y += pest.body.vy
            pests[i] = pest
            return
        }
        if pest.behavior == .rex, updateOffscreenRex(&pest) {
            pests[i] = pest
            return
        }
        pest.steer(players: players, physics: physics)
        if pest.updateStun() { events.append(.recover(x: pest.body.centerX, y: pest.body.top)) }
        pest.body.applyGravity(physics)
        let moved = pest.body.move(in: grid, isPlayer: false, wraps: pest.behavior != .rex)
        if moved.hitWall { pest.direction = -pest.direction }
        if let land = moved.landedOn { launchIfSpring(&pest.body, tile: land.tile, col: land.col, row: land.row) }
        if !pest.flipped && pest.body.vx != 0 { pest.direction = pest.body.vx > 0 ? 1 : -1 }

        // Bottom floor: walking off either edge sends the pest back up its pipe.
        if pest.behavior != .rex, pest.body.top > Units.screenH * 5 / 8, pest.body.left < -pest.body.w / 3 || pest.body.right > Units.screenW + pest.body.w / 3 {
            recycle(&pest)
        }
        // Fell out of the world (only possible in levels with holes in the floor).
        if pest.body.top > Units.screenH && pest.behavior != .rex { recycle(&pest) }

        // A bump under its feet this update flips it.
        if let (col, bump) = activeBump(under: pest.body), bump.id != pest.lastBumpID {
            pest.lastBumpID = bump.id
            if pest.behavior == .rex {
                hitRex(&pest, by: bump.player)
            } else {
                pest.bonk(from: col * Units.tileW + Units.tileW / 2, physics: physics)
            }
            events.append(.flip(x: pest.body.centerX, y: pest.body.top))
        }
        pests[i] = pest
    }

    /// A bump currently active under any part of a standing body's feet.
    private func activeBump(under body: Body) -> (col: Int, bump: Bump)? {
        guard body.grounded else { return nil }
        let row = body.bottom / Units.tileH
        for col in floorDiv(body.footLeft, Units.tileW)...floorDiv(body.footRight, Units.tileW) {
            if let b = bumps[Self.key(grid.wrapCol(col), row)] { return (grid.wrapCol(col), b) }
        }
        return nil
    }

    /// T. Wrecks: each bonk makes him hop and scores; the last one knocks him out.
    private func hitRex(_ rex: inout Pest, by player: Int?) {
        rex.body.vy = -128
        rex.body.grounded = false
        rex.hp -= 1
        let points = rex.hp > 0 ? 10_000 / max(level.boss?.hits ?? 1, 1) : rex.points
        if let player, players.indices.contains(player) {
            if players[player].addScore(points) { events.append(.extraLife(player: player)) }
            events.append(.kick(x: rex.body.centerX, y: rex.body.top, points: points, player: player, kind: "rex"))
        }
        events.append(.bossHit)
        if rex.hp <= 0 { rex.dead = true }
    }

    /// While T. Wrecks is off screen he waits, then charges back in on a random
    /// tier that has floor at the screen edge (0x41a956). Returns true while waiting.
    private func updateOffscreenRex(_ rex: inout Pest) -> Bool {
        let gone = rex.body.right < -60 || rex.body.left > Units.screenW + 60
        if gone && rex.offscreenTimer == 0 { rex.offscreenTimer = Int.random(in: 30...80) }
        guard rex.offscreenTimer > 0 else { return false }
        rex.offscreenTimer -= 1
        if rex.offscreenTimer == 0 {
            let edgeRows = (1..<Units.rows).filter { r in grid[0, r].isSolid(forPlayer: false) && !grid[0, r - 1].isSolid(forPlayer: false) }
            let row = edgeRows.randomElement() ?? Units.rows - 4
            let fromLeft = Bool.random()
            rex.direction = fromLeft ? 1 : -1
            rex.body = Body(w: rex.body.w, h: rex.body.h,
                            x: (fromLeft ? -rex.body.w : Units.screenW).sub, y: (row * Units.tileH - rex.body.h).sub)
            return false
        }
        rex.body.prevX = rex.body.x; rex.body.prevY = rex.body.y
        return true
    }

    private func recycle(_ pest: inout Pest) {
        let side: PipeSide = pest.home == .top ? .top : (pest.body.centerX < Units.screenW / 2 ? .left : .right)
        let cell = level.pipes[side]!
        let x = side == .right ? Units.screenW - pest.body.w : cell.col * Units.tileW
        pest.body = Body(w: pest.body.w, h: pest.body.h, x: x.sub, y: ((cell.row + 1) * Units.tileH - pest.body.h).sub)
        pest.direction = side == .right ? -1 : 1
    }

    private func updateGems() {
        for i in gems.indices {
            gems[i].life -= 1
            gems[i].body.applyGravity(physics)
            if gems[i].body.grounded && gems[i].body.vx == 0 { gems[i].body.vx = 24 }
            _ = gems[i].body.move(in: grid, isPlayer: false)
        }
        gems.removeAll { $0.life <= 0 || $0.body.top > Units.screenH }
    }

    /// A head hit a tile from below.
    func bump(col: Int, row: Int, by player: Int? = nil) {
        let tile = grid[col, row]
        guard tile.isBonkable, bumps[Self.key(col, row)] == nil else { return }
        bumps[Self.key(col, row)] = Bump(age: 0, id: nextID, player: player)
        nextID += 1
        events.append(.bump(col: col, row: row))
        if tile == .gem {
            grid[col, row] = .brick
            var body = Body(w: 14, h: 14, x: (col * Units.tileW + 9).sub, y: (row * Units.tileH - 16).sub)
            body.vy = -physics.pop
            body.vx = Bool.random() ? 24 : -24
            gems.append(Gem(id: nextID, body: body))
            nextID += 1
        }
    }

    // MARK: - Contacts: kicks, deaths, gems

    private func resolveContacts() {
        for pi in players.indices where players[pi].isAlive {
            for qi in pests.indices where !pests[qi].dead && players[pi].body.overlaps(pests[qi].body, inset: 4) {
                if pests[qi].flipped {
                    pests[qi].kick(by: players[pi], physics: physics)
                    let points = pests[qi].points * (1 + pests[qi].anger)
                    if players[pi].addScore(points) { events.append(.extraLife(player: pi)) }
                    events.append(.kick(x: pests[qi].body.centerX, y: pests[qi].body.top, points: points, player: pi,
                                        kind: pests[qi].kind?.rawValue ?? "shrew"))
                } else if players[pi].canBeHurt {
                    hurt(pi)
                    pests[qi].body.vy = -48
                }
            }
            for gi in gems.indices.reversed() where players[pi].body.overlaps(gems[gi].body) {
                if players[pi].addScore(500) { events.append(.extraLife(player: pi)) }
                events.append(.gem(x: gems[gi].body.centerX, y: gems[gi].body.top, player: pi))
                gems.remove(at: gi)
            }
        }
        bounceUprightPests()
    }

    private func hurt(_ i: Int) {
        players[i].lives -= 1
        players[i].state = .dying(ticks: 0)
        players[i].body.vy = -physics.jump * 3 / 4
        players[i].body.vx = 0
        players[i].body.grounded = false   // or gravity never pulls the tumble down
        events.append(.playerHit(player: i))
    }

    /// Two walking pests that meet turn around (Mario Bros. style).
    private func bounceUprightPests() {
        for a in pests.indices where pests[a].isDangerous && pests[a].body.grounded {
            for b in pests.indices where b > a && pests[b].isDangerous && pests[b].body.grounded {
                guard pests[a].body.overlaps(pests[b].body, inset: 2) else { continue }
                let aLeft = pests[a].body.centerX < pests[b].body.centerX
                if (pests[a].direction > 0) == aLeft { pests[a].direction = -pests[a].direction }
                if (pests[b].direction > 0) != aLeft { pests[b].direction = -pests[b].direction }
            }
        }
    }
}
