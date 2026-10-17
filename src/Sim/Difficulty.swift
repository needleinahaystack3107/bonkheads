/// Campaign progression: each level is a little tougher than the one before.
/// Step 0 is the level as written; every step makes pests ~8% faster, arrive
/// ~5% sooner and recover from a flip ~6% quicker, capped so late levels stay
/// fair. (The original had a similar global Easy/Normal/Hard scale in
/// FUN_0042209c: speeds x3/4 or x4/3.) Levels with "scaling": false opt out.
struct Difficulty {
    let step: Int

    static let none = Difficulty(step: 0)

    func speed(_ base: Int) -> Int { base * min(100 + 8 * step, 160) / 100 }
    func spawnTick(_ base: Int) -> Int { base * max(100 - 5 * step, 70) / 100 }
    func stunTicks(_ base: Int) -> Int { base == .max ? base : base * max(100 - 6 * step, 60) / 100 }

    var label: String { step == 0 ? "" : "+\(min(8 * step, 60))% speed" }
}
