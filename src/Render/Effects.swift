import SpriteKit

/// "Juice": particle bursts, screen shake and ambient weather. Everything is
/// purely visual; the simulation never reads any of it.
@MainActor
final class Effects {
    private let layer: SKNode
    private let shakeTarget: SKNode
    private static let dot = Art.texture(8, 8) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    private static let star = Art.texture(10, 10) { ctx in
        ctx.setFillColor(NSColor.white.cgColor)
        let pts = (0..<10).map { i -> CGPoint in
            let r: CGFloat = i % 2 == 0 ? 5 : 2
            let a = CGFloat(i) * .pi / 5 + .pi / 2
            return CGPoint(x: 5 + cos(a) * r, y: 5 + sin(a) * r)
        }
        ctx.addLines(between: pts)
        ctx.fillPath()
    }

    init(layer: SKNode, shakeTarget: SKNode) {
        self.layer = layer
        self.shakeTarget = shakeTarget
    }

    enum Shape { case dot, star }

    /// A one-shot burst at a scene position.
    func burst(at point: CGPoint, color: NSColor, count: Int, speed: CGFloat, spread: CGFloat = .pi * 2,
               angle: CGFloat = .pi / 2, shape: Shape = .dot, gravity: CGFloat = -300, scale: CGFloat = 0.6) {
        let e = SKEmitterNode()
        e.particleTexture = shape == .star ? Self.star : Self.dot
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .alpha
        e.numParticlesToEmit = count
        e.particleBirthRate = CGFloat(count) * 40
        e.particleLifetime = 0.55
        e.particleLifetimeRange = 0.3
        e.emissionAngle = angle
        e.emissionAngleRange = spread
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.6
        e.yAcceleration = gravity
        e.particleScale = scale
        e.particleScaleRange = scale * 0.5
        e.particleScaleSpeed = -scale
        e.particleAlphaSpeed = -1.4
        e.particleRotationSpeed = shape == .star ? 6 : 0
        e.position = point
        layer.addChild(e)
        e.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
    }

    /// A short decaying shake of the whole playfield.
    func shake(strength: CGFloat) {
        shakeTarget.removeAction(forKey: "shake")
        let steps = 8
        let moves = (0..<steps).map { i -> SKAction in
            let s = strength * CGFloat(steps - i) / CGFloat(steps)
            return .move(to: CGPoint(x: CGFloat.random(in: -s...s), y: CGFloat.random(in: -s...s)), duration: 0.025)
        }
        shakeTarget.run(.sequence(moves + [.move(to: .zero, duration: 0.03)]), withKey: "shake")
    }

    /// Continuous ambient particles for a level theme (bubbles, snow, embers, dust).
    static func ambience(for theme: Theme) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = dot
        e.particleColorBlendFactor = 1
        e.position = CGPoint(x: Units.screenW / 2, y: theme.ambientRisesUp ? -10 : Units.screenH + 10)
        e.particlePositionRange = CGVector(dx: Units.screenW, dy: 0)
        e.emissionAngle = theme.ambientRisesUp ? .pi / 2 : -.pi / 2
        e.emissionAngleRange = 0.4
        e.particleLifetime = 14
        e.particleSpeed = theme.ambientSpeed
        e.particleSpeedRange = theme.ambientSpeed / 2
        e.particleBirthRate = theme.ambientRate
        e.particleScale = 0.18
        e.particleScaleRange = 0.12
        e.particleAlpha = 0.35
        e.particleAlphaRange = 0.2
        e.particleColor = theme.ambientColor
        e.xAcceleration = 3
        e.advanceSimulationTime(14)   // start with the screen already full
        return e
    }
}
