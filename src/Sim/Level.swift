import Foundation

// The custom level format (documented for humans in docs/making-levels.md).
// Decoding is two-step: `LevelFile` mirrors the JSON exactly, then
// `Level.init(file:)` validates it into the form the game uses. The game and
// the `--validate` command share this one path.

struct LevelFile: Decodable {
    var name: String
    var author: String?
    var hint: String?
    var theme: String?
    var physics: PhysicsSpec?
    var tiles: [String]
    var pests: [PestSpec]
    var boss: BossSpec?
    var pipes: PipeSpec?
    var tutorial: [String: String]?   // event -> coaching caption (see making-levels.md)
    var scaling: Bool?          // false: play exactly as written (no campaign progression)

    struct PestSpec: Decodable { var kind: String; var at: Double; var from: String?; var speed: Int? }
    struct BossSpec: Decodable { var kind: String?; var hits: Int; var at: Double }
    struct PipeSpec: Decodable { var left: [Int]?; var right: [Int]?; var top: [Int]? }
}

/// `"physics": "ice"` or `"physics": { "preset": "ice", "gravity": 12 }`.
struct PhysicsSpec: Decodable {
    var value: Physics

    private struct Overrides: Decodable {
        var preset: String?
        var gravity, friction, jump, maxWalk, accel, pop: Int?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let name = try? c.decode(String.self) {
            guard let p = Physics.presets[name] else {
                throw LevelError("unknown physics preset \"\(name)\" (use \(Physics.presets.keys.sorted().joined(separator: ", ")))")
            }
            value = p
            return
        }
        let o = try c.decode(Overrides.self)
        var p = Physics.normal
        if let name = o.preset {
            guard let preset = Physics.presets[name] else { throw LevelError("unknown physics preset \"\(name)\"") }
            p = preset
        }
        p.gravity = o.gravity ?? p.gravity
        p.friction = o.friction ?? p.friction
        p.jump = o.jump ?? p.jump
        p.maxWalk = o.maxWalk ?? p.maxWalk
        p.accel = o.accel ?? p.accel
        p.pop = o.pop ?? p.pop
        value = p
    }
}

struct LevelError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

enum PipeSide: String { case left, right, top }

struct Level {
    struct Cell { var col: Int; var row: Int }
    struct Spawn { var tick: Int; var kind: PestKind; var side: PipeSide; var speed: Int }
    struct Boss { var tick: Int; var hits: Int; var look: String }

    let name: String
    let hint: String?
    let scales: Bool
    let tutorial: [String: String]
    static let tutorialEvents: Set<String> = ["start", "bump", "flip", "kick", "recover", "hit", "gem", "spring"]
    let theme: String?   // visual only; resolved by the renderer
    let physics: Physics
    let grid: TileGrid
    let starts: [Cell]              // player 1, player 2
    let pipes: [PipeSide: Cell]
    let spawns: [Spawn]             // sorted by tick
    let boss: Boss?

    init(file: LevelFile) throws {
        name = file.name
        hint = file.hint
        scales = file.scaling ?? true
        tutorial = file.tutorial ?? [:]
        if let bad = tutorial.keys.first(where: { !Level.tutorialEvents.contains($0) }) {
            throw LevelError("tutorial key \"\(bad)\" is not an event (use \(Level.tutorialEvents.sorted().joined(separator: ", ")))")
        }
        theme = file.theme
        physics = file.physics?.value ?? .normal

        // Tiles: exactly 30 rows of 20 characters; '1'/'2' mark player starts.
        guard file.tiles.count == Units.rows else {
            throw LevelError("tiles must have \(Units.rows) rows, found \(file.tiles.count)")
        }
        var rows: [[Tile]] = []
        var found: [Character: Cell] = [:]
        for (r, line) in file.tiles.enumerated() {
            guard line.count == Units.cols else {
                throw LevelError("tiles row \(r + 1) must be \(Units.cols) characters, found \(line.count)")
            }
            rows.append(try line.enumerated().map { c, ch in
                if ch == "1" || ch == "2" {
                    if found[ch] != nil { throw LevelError("more than one player \(ch) start") }
                    found[ch] = Cell(col: c, row: r)
                    return .empty
                }
                guard let tile = Tile(rawValue: ch) else {
                    throw LevelError("row \(r + 1), column \(c + 1): unknown tile '\(ch)'")
                }
                return tile
            })
        }
        grid = TileGrid(rows: rows)
        guard let p1 = found["1"] else { throw LevelError("missing player 1 start ('1' in tiles)") }
        // No '2'? Mirror player 1 across the screen.
        starts = [p1, found["2"] ?? Cell(col: Units.cols - 1 - p1.col, row: p1.row)]

        var pipes: [PipeSide: Cell] = [.left: Cell(col: 0, row: 4), .right: Cell(col: 19, row: 4),
                                       .top: Cell(col: 9, row: 0)]
        for (side, cell) in [(PipeSide.left, file.pipes?.left), (.right, file.pipes?.right), (.top, file.pipes?.top)] {
            guard let cell else { continue }
            guard cell.count == 2, (0..<Units.cols).contains(cell[0]), (0..<Units.rows).contains(cell[1]) else {
                throw LevelError("pipes.\(side.rawValue) must be [column, row] inside the grid")
            }
            pipes[side] = Cell(col: cell[0], row: cell[1])
        }
        self.pipes = pipes

        // Pests: unspecified sides alternate left/right, like the original pipes.
        spawns = try file.pests.enumerated().map { i, spec in
            guard let kind = PestKind(rawValue: spec.kind.lowercased()) else {
                throw LevelError("pest \(i + 1): unknown kind \"\(spec.kind)\" (use \(PestKind.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            if let s = spec.speed, !(1...200).contains(s) { throw LevelError("pest \(i + 1): speed must be 1-200") }
            guard spec.at >= 0 else { throw LevelError("pest \(i + 1): \"at\" must be >= 0 seconds") }
            let side = try spec.from.map { name -> PipeSide in
                guard let s = PipeSide(rawValue: name) else { throw LevelError("pest \(i + 1): from must be left, right or top") }
                return s
            } ?? (kind.traits.fromTop ? .top : (i.isMultiple(of: 2) ? .left : .right))
            return Spawn(tick: Units.ticks(seconds: spec.at), kind: kind, side: side, speed: spec.speed ?? kind.traits.speed)
        }.sorted { $0.tick < $1.tick }

        if let b = file.boss {
            guard (1...20).contains(b.hits) else { throw LevelError("boss.hits must be 1-20") }
            boss = Boss(tick: Units.ticks(seconds: b.at), hits: b.hits, look: b.kind ?? "shrew")
        } else {
            boss = nil
        }
        guard !spawns.isEmpty || boss != nil else { throw LevelError("a level needs at least one pest or a boss") }
    }

    static func load(_ url: URL) throws -> Level {
        let data = try Data(contentsOf: url)
        do {
            return try Level(file: JSONDecoder().decode(LevelFile.self, from: data))
        } catch let error as DecodingError {
            throw LevelError(describe(error))
        }
    }

    /// All `*.json` files in a folder, in filename order, with per-file results.
    static func loadAll(in folder: URL) -> [(url: URL, result: Result<Level, Error>)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in (url, Result { try load(url) }) }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let ctx): return "missing \"\(key.stringValue)\"\(path(ctx))"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx): return "wrong type\(path(ctx)): \(ctx.debugDescription)"
        case .dataCorrupted(let ctx):
            return (ctx.underlyingError as? LevelError)?.description ?? "invalid JSON\(path(ctx)): \(ctx.debugDescription)"
        @unknown default: return "\(error)"
        }
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        ctx.codingPath.isEmpty ? "" : " at " + ctx.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
}
