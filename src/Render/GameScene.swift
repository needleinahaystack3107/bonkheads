import SpriteKit

/// Runs the fixed-tick simulation and draws it. The simulation advances every
/// 34 ms exactly like the original; rendering interpolates between the last
/// two updates so motion is smooth at 60/120 Hz.
@MainActor
final class GameScene: SKScene {
    enum Mode { case menu, playing, cleared(ticks: Int) }

    private let levels: [Level]
    /// Debug/demo options from the command line (see main.swift).
    var autoplay = false
    /// Original sprites exported from the user's own demo files, if present.
    var originalArt: OriginalArt?
    /// Original sounds and music, if exported.
    var sound: SoundPlayer?
    private let loadErrors: [String]
    private var mode = Mode.menu
    private var activeMenu: MenuNode?
    private var game: Game?
    private var levelIndex = 0
    private var playerCount = 1

    private var keys = Set<UInt16>()
    private var accumulator = 0.0
    private var lastTime: TimeInterval?

    private let world = SKNode()
    private let backdrop = SKSpriteNode()
    private var ambience: SKEmitterNode?
    private let shadowLayer = SKNode()
    private let tileLayer = SKNode()
    private let fxLayer = SKNode()
    private lazy var effects = Effects(layer: fxLayer, shakeTarget: world)
    /// Squash & stretch per actor key: 1 = normal, >1 = squashed wide.
    private var squash: [String: CGFloat] = [:]
    private let actorLayer = SKNode()
    private let hud = SKNode()
    private let overlay = SKNode()
    private var tileNodes: [Int: SKSpriteNode] = [:]
    private var actorNodes: [String: WrappedSprite] = [:]
    private var scoreLabels: [SKLabelNode] = []

    private let trollTextures = [Art.troll(skin: 0x8BD46B, hair: 0xFF5A5A, shirt: 0x3E7BD9),
                                 Art.troll(skin: 0xE8B27C, hair: 0xB06CFF, shirt: 0xF0A030)]
    private var pestTextures: [String: SKTexture] = [:]

    init(levels: [Level], loadErrors: [String]) {
        self.levels = levels
        self.loadErrors = loadErrors
        super.init(size: CGSize(width: Units.screenW, height: Units.screenH))
        scaleMode = .aspectFit
        backgroundColor = .black
        backdrop.anchorPoint = .zero
        backdrop.size = size
        backdrop.zPosition = -10
        world.addChild(backdrop)
        shadowLayer.zPosition = 0.5
        tileLayer.zPosition = 1
        actorLayer.zPosition = 2
        fxLayer.zPosition = 3
        let vignette = SKSpriteNode(texture: Art.vignette)
        vignette.anchorPoint = .zero
        vignette.size = size
        vignette.zPosition = 5
        world.addChild(shadowLayer)
        world.addChild(fxLayer)
        world.addChild(vignette)
        apply(theme: .cave)
        hud.zPosition = 10
        overlay.zPosition = 20
        world.addChild(tileLayer)
        world.addChild(actorLayer)
        addChild(world)
        addChild(hud)
        addChild(overlay)
        showMainMenu()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Input (original default keys: findings.md, "Input and 2-player controls")

    private enum Key {
        static let left: UInt16 = 123, right: UInt16 = 124, up: UInt16 = 126
        static let a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2
        static let m: UInt16 = 46
        static let one: UInt16 = 18, two: UInt16 = 19, enter: UInt16 = 36, esc: UInt16 = 53, space: UInt16 = 49
    }

    private func input(for player: Int) -> PlayerInput {
        player == 0
            ? PlayerInput(left: keys.contains(Key.left), right: keys.contains(Key.right), jump: keys.contains(Key.up))
            : PlayerInput(left: keys.contains(Key.a), right: keys.contains(Key.d), jump: keys.contains(Key.s))
    }

    override func keyDown(with event: NSEvent) {
        keys.insert(event.keyCode)
        guard !event.isARepeat else { return }
        if event.keyCode == Key.m { sound?.toggleMusic(); return }
        switch mode {
        case .menu: _ = activeMenu?.handle(keyCode: event.keyCode)
        case .playing where event.keyCode == Key.esc: showPauseMenu()
        default: break
        }
    }

    override func keyUp(with event: NSEvent) { keys.remove(event.keyCode) }

    // MARK: - Flow

    /// Starts the campaign at `index`; later levels follow in order.
    func start(players: Int, at index: Int = 0) {
        guard levels.indices.contains(index) else { return }
        playerCount = players
        load(level: index, carryOver: nil)
    }

    private func load(level index: Int, carryOver: [Player]?) {
        levelIndex = index
        let level = levels[index]
        game = Game(level: level, playerCount: playerCount, carryOver: carryOver, difficulty: Difficulty(step: index))
        apply(theme: Theme.resolve(level.theme, physics: level.physics))
        rebuildTiles()
        actorNodes.values.forEach { $0.removeFromParent() }
        actorNodes.removeAll()
        buildHUD()
        closeMenu()
        mode = .playing
        banner("Level \(index + 1): \(level.name)", sub: level.hint, seconds: 2.5)
    }

    // MARK: - Menus

    private func present(_ m: MenuNode) {
        activeMenu?.removeFromParent()
        activeMenu = m
        overlay.addChild(m)
        mode = .menu
    }

    private func closeMenu() {
        activeMenu?.removeFromParent()
        activeMenu = nil
    }

    private func quit() { NSApp.terminate(nil) }

    private func clearPlayfield() {
        game = nil
        tileLayer.removeAllChildren(); tileNodes.removeAll(); shadowLayer.removeAllChildren()
        actorNodes.values.forEach { $0.removeFromParent() }; actorNodes.removeAll()
        hud.removeAllChildren()
        overlay.removeAllChildren()
        activeMenu = nil
    }

    func showMainMenu() {
        clearPlayfield()
        apply(theme: .cave)
        var subtitle = "Bonk pests from below, then kick them away!"
        if levels.isEmpty { subtitle = "No playable levels: add .json files to levels/" }
        else if !loadErrors.isEmpty { subtitle = "\(loadErrors.count) level file(s) have errors: run --validate" }
        present(MenuNode(
            title: "BONKHEADS",
            subtitle: subtitle,
            items: [
                .init("1 Player") { [unowned self] in start(players: 1) },
                .init("2 Players") { [unowned self] in start(players: 2) },
                .init("Select Level", detail: "\(levels.count) levels") { [unowned self] in showLevelSelect() },
                .init("Quit") { [unowned self] in quit() },
            ],
            footer: "P1: ← → walk, ↑ jump   ·   P2: A D walk, S jump   ·   M music   ·   Esc pause"))
    }

    func showLevelSelect(selected: Int = 1) {
        var players = playerCount
        var items: [MenuNode.Item] = [
            .init(dynamic: { "Players:  ◀ \(players) ▶" }, adjust: { delta in players = delta < 0 ? 1 : 2 },
                  action: { players = players == 1 ? 2 : 1 }),
        ]
        items += levels.enumerated().map { i, level in
            let harder = level.scales ? Difficulty(step: i).label : "as original"
            let detail = "\(level.spawns.count) pests" + (level.boss != nil ? " + boss" : "") + (harder.isEmpty ? "" : " · \(harder)")
            return MenuNode.Item("\(i + 1). \(level.name)", detail: detail) { [unowned self] in
                start(players: players, at: i)
            }
        }
        items.append(.init("Back") { [unowned self] in showMainMenu() })
        present(MenuNode(title: "Select Level", subtitle: "Levels get a little tougher as you go",
                         items: items, selected: selected,
                         footer: "↑ ↓ choose   ·   ← → players   ·   Enter play   ·   Esc back",
                         onBack: { [unowned self] in showMainMenu() }))
    }

    private func showPauseMenu() {
        present(MenuNode(
            title: "Paused",
            subtitle: "Level \(levelIndex + 1): \(levels[levelIndex].name)",
            items: [
                .init("Resume") { [unowned self] in closeMenu(); mode = .playing },
                .init("Restart Level") { [unowned self] in load(level: levelIndex, carryOver: nil) },
                .init("Main Menu") { [unowned self] in showMainMenu() },
                .init("Quit") { [unowned self] in quit() },
            ],
            onBack: { [unowned self] in closeMenu(); mode = .playing }))
    }

    private func scoreLine(_ game: Game) -> String {
        game.players.map { "P\($0.index + 1): \($0.score)" }.joined(separator: "    ")
    }

    private func showGameOver(_ game: Game) {
        present(MenuNode(
            title: "Game Over",
            subtitle: scoreLine(game),
            items: [
                .init("Retry Level \(levelIndex + 1)") { [unowned self] in load(level: levelIndex, carryOver: nil) },
                .init("Main Menu") { [unowned self] in showMainMenu() },
                .init("Quit") { [unowned self] in quit() },
            ]))
    }

    private func showVictory(_ game: Game) {
        present(MenuNode(
            title: "You beat them all!",
            subtitle: scoreLine(game),
            items: [
                .init("Main Menu") { [unowned self] in showMainMenu() },
                .init("Quit") { [unowned self] in quit() },
            ]))
    }

    private func apply(theme: Theme) {
        backdrop.texture = Art.backdrop(top: theme.skyTop, bottom: theme.skyBottom)
        ambience?.removeFromParent()
        let a = Effects.ambience(for: theme)
        a.zPosition = -5
        world.addChild(a)
        ambience = a
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        // Clamp: a long hitch must not fast-forward the game, and time must not run backwards.
        let dt = min(max(currentTime - (lastTime ?? currentTime), 0), 0.25)
        lastTime = currentTime
        guard let game else { return }

        switch mode {
        case .playing, .cleared:
            accumulator += dt
            while accumulator >= Units.tickSeconds {
                accumulator -= Units.tickSeconds
                fixedStep(game)
            }
        default:
            break
        }
        render(game, alpha: CGFloat(accumulator / Units.tickSeconds))
    }

    private func fixedStep(_ game: Game) {
        if case .cleared(let t) = mode {
            if t > Units.ticks(seconds: 2.5) {
                if levelIndex + 1 < levels.count { load(level: levelIndex + 1, carryOver: game.players) }
                else { showVictory(game) }
            }
            else { mode = .cleared(ticks: t + 1) }
            return
        }
        game.step(inputs: (0..<playerCount).map { i in
            autoplay ? Autopilot.input(for: game.players[i], in: game) : input(for: i)
        })
        handle(game.events)
        if game.isOver {
            showGameOver(game)
        } else if game.isCleared {
            mode = .cleared(ticks: 0)
            sound?.play("levelClear")
            banner("Level clear!", sub: nil, seconds: 2)
        }
    }

    /// Turns simulation events into particles, shake, squash and score popups.
    private func handle(_ events: [GameEvent]) {
        guard let game else { return }
        func at(_ x: Int, _ y: Int) -> CGPoint { CGPoint(x: x, y: Units.screenH - y) }
        for e in events {
            switch e {
            case .bump(let col, let row):
                effects.burst(at: at(col * Units.tileW + 16, (row + 1) * Units.tileH), color: Art.color(0xF2C9A0),
                              count: 10, speed: 70, spread: 1.2, angle: -.pi / 2, gravity: -120, scale: 0.4)
                effects.shake(strength: 1.5)
                sound?.play("bump")
            case .flip(let x, let y):
                effects.burst(at: at(x, y), color: Art.color(0xFFF07A), count: 8, speed: 110, shape: .star)
            case .kick(let x, let y, let points, _, let kind):
                sound?.play("kick.\(kind)")
                popup("+\(points)", x: x, y: y)
                effects.burst(at: at(x, y + 10), color: Art.color(0xFFD23F), count: 22, speed: 190, shape: .star, scale: 0.9)
                effects.shake(strength: 4)
            case .gem(let x, let y, _):
                popup("+500", x: x, y: y)
                sound?.play("gem")
                effects.burst(at: at(x, y), color: Art.color(0x7CF7FF), count: 18, speed: 140, shape: .star)
            case .bossHit:
                sound?.play("rexHit")
            case .extraLife(let p):
                sound?.play("extraLife")
                popup("1UP!", x: game.players[p].body.centerX, y: game.players[p].body.top)
            case .playerHit(let p):
                let b = game.players[p].body
                effects.burst(at: at(b.centerX, b.top + 20), color: .white, count: 26, speed: 160, gravity: 0, scale: 0.8)
                effects.shake(strength: 7)
                sound?.play("playerHit")
            case .spring(let col, let row):
                sound?.play(game.grid[col, row] == .superSpring ? "superSpring" : "spring")
                effects.burst(at: at(col * Units.tileW + 16, row * Units.tileH), color: Art.color(0x9CFFB0),
                              count: 12, speed: 120, spread: 0.8, scale: 0.5)
            case .jump(let p):
                squash["p\(p)"] = 0.75
            case .land(let p):
                squash["p\(p)"] = 1.3
                let b = game.players[p].body
                effects.burst(at: at(b.centerX, b.bottom), color: Art.color(0xFFFFFF, 0.8), count: 6, speed: 50,
                              spread: 0.6, angle: .pi / 2, gravity: -60, scale: 0.35)
            }
        }
    }

    /// Eases squash/stretch back to 1 and returns (xScale, yScale) for an actor.
    private func squashScale(_ key: String, grounded: Bool, vy: Int) -> (CGFloat, CGFloat) {
        var s = squash[key] ?? 1
        s += (1 - s) * 0.18
        squash[key] = s
        // Airborne actors also stretch a little with vertical speed.
        let stretch = grounded ? 1 : 1 + min(CGFloat(abs(vy)) / 2400, 0.08)
        return (s / stretch, stretch / s)
    }

    // MARK: - Drawing

    private func scenePoint(_ x: CGFloat, _ yTop: CGFloat, w: Int, h: Int) -> CGPoint {
        CGPoint(x: x + CGFloat(w) / 2, y: CGFloat(Units.screenH) - yTop - CGFloat(h) / 2)
    }

    private func interpolated(_ b: Body, _ alpha: CGFloat) -> CGPoint {
        let x = CGFloat(b.prevX) + CGFloat(b.x - b.prevX) * alpha
        let y = CGFloat(b.prevY) + CGFloat(b.y - b.prevY) * alpha
        return scenePoint(x / 16, y / 16, w: b.w, h: b.h)
    }

    private func rebuildTiles() {
        tileLayer.removeAllChildren()
        tileNodes.removeAll()
        guard let game else { return }
        for row in 0..<Units.rows {
            for col in 0..<Units.cols where game.grid[col, row] != .empty {
                let node = SKSpriteNode(texture: tileTexture(game, col, row), size: CGSize(width: Units.tileW, height: Units.tileH))
                node.position = scenePoint(CGFloat(col * Units.tileW), CGFloat(row * Units.tileH), w: Units.tileW, h: Units.tileH)
                tileLayer.addChild(node)
                tileNodes[Game.key(col, row)] = node
                if game.grid[col, row - 1] != .floor {
                    let shadow = SKSpriteNode(color: .black, size: node.size)
                    shadow.alpha = 0.28
                    shadow.position = CGPoint(x: node.position.x + 3, y: node.position.y - 5)
                    shadowLayer.addChild(shadow)
                }
            }
        }
    }

    private func tileTexture(_ game: Game, _ col: Int, _ row: Int) -> SKTexture {
        game.grid[col, row] == .floor && game.grid[col, row - 1] != .empty ? Art.earth : Art.tile(game.grid[col, row])
    }

    private func render(_ game: Game, alpha: CGFloat) {
        // Tiles: bumped tiles hop up and back down; gem bricks may have changed.
        for (key, node) in tileNodes {
            let col = key % Units.cols, row = key / Units.cols
            node.texture = tileTexture(game, col, row)
            let base = scenePoint(CGFloat(col * Units.tileW), CGFloat(row * Units.tileH), w: Units.tileW, h: Units.tileH)
            let lift = game.bumps[key].map { sin(CGFloat($0.age) / CGFloat(Game.bumpTicks) * .pi) * 7 } ?? 0
            node.position = CGPoint(x: base.x, y: base.y + lift)
        }

        var seen = Set<String>()
        for p in game.players where p.state != .out {
            if case .waiting = p.state { continue }
            let key = "p\(p.index)"
            seen.insert(key)
            let node = actor(key, texture: trollTextures[p.index], size: CGSize(width: 36, height: 44))
            node.position = interpolated(p.body, alpha)
            let dying: Bool = { if case .dying = p.state { return true }; return false }()
            let (sx, sy) = squashScale(key, grounded: p.body.grounded, vy: p.body.vy)
            let wobble = p.body.grounded && p.body.vx != 0 ? sin(CGFloat(p.body.x) / 160) * 0.09 : 0
            if let tex = originalFrame(player: p, dying: dying) {
                // Original art has its own walk cycle and facing; keep only a light squash.
                let h = tex.size().height
                node.style(texture: tex, size: tex.size(), xScale: sx, yScale: sy,
                           offsetY: (h - CGFloat(p.body.h)) / 2 + (sy - 1) * h / 2)
            } else {
                node.style(xScale: CGFloat(p.facing) * sx, yScale: sy, rotation: dying ? .pi : wobble,
                           offsetY: 2 + (sy - 1) * 22)
            }
            node.alpha = p.invulnerable > 0 && (p.invulnerable / 4) % 2 == 0 ? 0.35 : 1
        }
        for pest in game.pests {
            let key = "e\(pest.id)"
            seen.insert(key)
            let size = CGSize(width: pest.body.w + 8, height: pest.body.h + 6)
            let node = actor(key, texture: pestTexture(pest), size: size)
            node.position = interpolated(pest.body, alpha)
            let shake: CGFloat = pest.isShaking ? CGFloat((game.tick % 2) * 2 - 1) * 1.5 : 0
            node.position.x += shake
            if let tex = originalFrame(pest: pest, tick: game.tick) {
                let h = tex.size().height
                node.style(texture: tex, size: tex.size(), xScale: 1, offsetY: (h - CGFloat(pest.body.h)) / 2,
                           tint: pest.anger > 0 && pest.behavior != .rex ? .red : nil)
                continue
            }
            let waddle = pest.body.grounded && !pest.flipped ? sin(CGFloat(pest.body.x) / 90) * 0.08 : 0
            let spin = pest.dead ? CGFloat(game.tick) * 0.5 : 0
            node.style(texture: pestTexture(pest), xScale: CGFloat(pest.direction),
                       rotation: (pest.flipped || pest.dead ? .pi : waddle) + spin, offsetY: 2)
        }
        for gem in game.gems {
            let key = "g\(gem.id)"
            seen.insert(key)
            let node = actor(key, texture: Art.gem, size: CGSize(width: 14, height: 14))
            node.position = interpolated(gem.body, alpha)
            node.alpha = gem.life < 60 && (gem.life / 4) % 2 == 0 ? 0.3 : 1
        }
        for (key, node) in actorNodes where !seen.contains(key) {
            node.removeFromParent()
            actorNodes[key] = nil
        }

        for (i, label) in scoreLabels.enumerated() where i < game.players.count {
            let p = game.players[i]
            label.text = "P\(i + 1)  \(p.score)   " + String(repeating: "♥", count: max(p.lives, 0))
        }
    }

    private func actor(_ key: String, texture: SKTexture, size: CGSize) -> WrappedSprite {
        if let n = actorNodes[key] { return n }
        let n = WrappedSprite(texture: texture, size: size)
        actorLayer.addChild(n)
        actorNodes[key] = n
        return n
    }

    /// Walk cycles advance with distance travelled (6 px per frame), like a real gait.
    private func walkStep(_ body: Body) -> Int { abs(body.x.px) / 6 }

    private func originalFrame(player p: Player, dying: Bool) -> SKTexture? {
        guard let art = originalArt else { return nil }
        let name = "troll\(p.index + 1)"
        if dying { return art.frame(name, "hit", step: 0) }
        let step = p.body.grounded && p.body.vx != 0 ? walkStep(p.body) : (p.body.grounded ? 0 : 2)
        return art.frame(name, p.facing > 0 ? "right" : "left", step: step)
    }

    private func originalFrame(pest: Pest, tick: Int) -> SKTexture? {
        guard let art = originalArt else { return nil }
        let name = pest.behavior == .rex ? "rex" : (pest.kind?.rawValue ?? "shrew")
        guard art.has(name) else { return nil }
        if pest.dead { return art.frame(name, "kicked", step: tick / 2) ?? art.frame(name, "right", step: 0) }
        if pest.flipped { return art.frame(name, "stunned", step: tick / 3) }
        let step = pest.behavior == .hop || pest.behavior == .rex ? tick / 3 : walkStep(pest.body)
        return art.frame(name, pest.direction > 0 ? "right" : "left", step: step)
    }

    private func pestTexture(_ pest: Pest) -> SKTexture {
        let key = "\(pest.kind?.rawValue ?? "boss")-\(pest.anger > 0)"
        if let t = pestTextures[key] { return t }
        let t = Art.pest(pest.kind, w: CGFloat(pest.body.w), h: CGFloat(pest.body.h), angry: pest.anger > 0)
        pestTextures[key] = t
        return t
    }

    // MARK: - HUD and text

    private func buildHUD() {
        hud.removeAllChildren()
        let levelLabel = label("Level \(levelIndex + 1) / \(levels.count)", size: 13)
        levelLabel.position = CGPoint(x: CGFloat(Units.screenW) / 2, y: CGFloat(Units.screenH - 22))
        levelLabel.fontColor = NSColor(white: 1, alpha: 0.75)
        hud.addChild(levelLabel)
        overlay.removeAllChildren()
        scoreLabels = (0..<playerCount).map { i in
            let l = label("", size: 15)
            l.horizontalAlignmentMode = i == 0 ? .left : .right
            l.position = CGPoint(x: i == 0 ? 16 : CGFloat(Units.screenW - 16), y: CGFloat(Units.screenH - 22))
            let pill = SKShapeNode(rectOf: CGSize(width: 170, height: 24), cornerRadius: 12)
            pill.fillColor = NSColor(white: 0, alpha: 0.4)
            pill.strokeColor = NSColor(white: 1, alpha: 0.15)
            pill.position = CGPoint(x: i == 0 ? 91 : CGFloat(Units.screenW - 91), y: CGFloat(Units.screenH - 17))
            hud.addChild(pill)
            hud.addChild(l)
            return l
        }
    }

    private func label(_ text: String, size: CGFloat) -> SKLabelNode {
        let l = SKLabelNode(text: text)
        l.fontName = "AvenirNext-Heavy"
        l.fontSize = size
        l.fontColor = .white
        return l
    }

    private func banner(_ text: String, sub: String?, seconds: Double) {
        let node = SKNode()
        let backing = SKShapeNode(rectOf: CGSize(width: 560, height: sub == nil ? 56 : 80), cornerRadius: 16)
        backing.fillColor = NSColor(white: 0, alpha: 0.55)
        backing.strokeColor = .clear
        backing.position.y = sub == nil ? 10 : -2
        node.addChild(backing)
        let title = label(text, size: 30)
        node.addChild(title)
        if let sub {
            let s = label(sub, size: 13)
            s.position.y = -24
            s.fontName = "AvenirNext-DemiBold"
            node.addChild(s)
        }
        node.position = CGPoint(x: Units.screenW / 2, y: Units.screenH / 2 + 40)
        overlay.addChild(node)
        node.run(.sequence([.wait(forDuration: seconds), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }

    private func popup(_ text: String, x: Int, y: Int) {
        let l = label(text, size: 14)
        l.fontColor = NSColor(srgbRed: 1, green: 0.9, blue: 0.3, alpha: 1)
        l.position = CGPoint(x: x, y: Units.screenH - y + 6)
        overlay.addChild(l)
        l.run(.sequence([.group([.moveBy(x: 0, y: 26, duration: 0.8), .fadeOut(withDuration: 0.8)]), .removeFromParent()]))
    }
}
