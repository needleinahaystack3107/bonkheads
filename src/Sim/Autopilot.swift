/// A very simple computer player, used by `--autoplay` for demos and for
/// screenshot checks. It walks under the nearest pest and jumps to bonk it,
/// then walks into flipped pests to kick them.
enum Autopilot {
    static func input(for player: Player, in game: Game) -> PlayerInput {
        guard player.isAlive else { return PlayerInput() }
        let me = player.body
        var input = PlayerInput()
        let live = game.pests.filter { !$0.dead }

        if let target = live.filter(\.flipped).min(by: { distance(me, $0.body) < distance(me, $1.body) }) {
            // Go and kick it.
            input.right = target.body.centerX > me.centerX
            input.left = !input.right
            input.jump = target.body.bottom < me.bottom - 8 && game.tick % 20 < 10
        } else if let target = live.filter({ (90...130).contains(me.bottom - $0.body.bottom) })
                    .min(by: { distance(me, $0.body) < distance(me, $1.body) }) {
            // It walks on the tier just above: stand under it and bonk.
            let dx = target.body.centerX - me.centerX
            input.right = dx > 6
            input.left = dx < -6
            input.jump = abs(dx) < 20 && game.tick % 12 < 6
        } else if let threat = live.first(where: { abs($0.body.centerX - me.centerX) < 50 && abs($0.body.bottom - me.bottom) < 10 }) {
            // Something is walking at us on our floor: jump over it.
            input.jump = true
            input.right = threat.body.centerX < me.centerX
            input.left = !input.right
        }
        return input
    }

    private static func distance(_ a: Body, _ b: Body) -> Int { abs(a.centerX - b.centerX) + abs(a.bottom - b.bottom) }
}
