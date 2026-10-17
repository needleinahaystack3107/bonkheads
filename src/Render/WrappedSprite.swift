import SpriteKit

/// A sprite that is also drawn one screen-width to each side, so actors slide
/// smoothly across the wraparound edge instead of popping (the original popped).
final class WrappedSprite: SKNode {
    let main: SKSpriteNode
    private let ghosts: [SKSpriteNode]

    init(texture: SKTexture, size: CGSize) {
        main = SKSpriteNode(texture: texture, size: size)
        ghosts = [-1, 1].map { side in
            let g = SKSpriteNode(texture: texture, size: size)
            g.position.x = CGFloat(side * Units.screenW)
            return g
        }
        super.init()
        addChild(main)
        ghosts.forEach(addChild)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Apply the same look to the main sprite and both edge copies.
    func style(texture: SKTexture? = nil, size: CGSize? = nil, xScale: CGFloat, yScale: CGFloat = 1,
               rotation: CGFloat = 0, offsetY: CGFloat = 0, tint: NSColor? = nil) {
        for (i, s) in ([main] + ghosts).enumerated() {
            if let texture, s.texture !== texture { s.texture = texture }
            if let size { s.xScale = 1; s.yScale = 1; s.size = size }   // size is post-scale, so reset first
            s.color = tint ?? .white
            s.colorBlendFactor = tint == nil ? 0 : 0.35
            s.xScale = xScale
            s.yScale = yScale
            s.zRotation = rotation
            s.position.y = offsetY
            if i > 0 { s.position.x = CGFloat((i == 1 ? -1 : 1) * Units.screenW) }
        }
    }
}
