import AppKit
import SpriteKit

/// Original placeholder art, drawn with Core Graphics at launch (no image files,
/// nothing taken from the original game). Textures are rendered at 3x so they
/// stay crisp when the 640x480 scene is scaled up on a Retina display.
@MainActor
enum Art {
    static let scale: CGFloat = 3

    static func texture(_ w: CGFloat, _ h: CGFloat, _ draw: (CGContext) -> Void) -> SKTexture {
        let ctx = CGContext(data: nil, width: Int(w * scale), height: Int(h * scale), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)   // draw in points, rasterise at 3x
        draw(ctx)
        let tex = SKTexture(cgImage: ctx.makeImage()!)
        tex.filteringMode = .linear
        return tex
    }

    nonisolated static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func gradient(_ ctx: CGContext, _ rect: CGRect, top: UInt32, bottom: UInt32) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(bottom).cgColor, color(top).cgColor] as CFArray, locations: [0, 1])!
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        ctx.restoreGState()
    }

    // MARK: Tiles (32x16)

    private static var tileCache: [Tile: SKTexture] = [:]

    static func tile(_ t: Tile) -> SKTexture {
        if let cached = tileCache[t] { return cached }
        let r = CGRect(x: 0, y: 0, width: 32, height: 16)
        let tex = texture(32, 16) { ctx in
            switch t {
            case .brick, .gem:
                gradient(ctx, r.insetBy(dx: 0.5, dy: 0.5), top: 0xE07A3F, bottom: 0x9C3D1E)
                ctx.setStrokeColor(color(0x5A200E).cgColor); ctx.setLineWidth(1)
                ctx.stroke(CGRect(x: 0.5, y: 0.5, width: 31, height: 15))
                ctx.move(to: CGPoint(x: 0, y: 8)); ctx.addLine(to: CGPoint(x: 32, y: 8))
                for x in [10.0, 26.0] { ctx.move(to: CGPoint(x: x, y: 8)); ctx.addLine(to: CGPoint(x: x, y: 16)) }
                for x in [4.0, 18.0] { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: 8)) }
                ctx.strokePath()
                ctx.setFillColor(color(0xFFFFFF, 0.25).cgColor); ctx.fill(CGRect(x: 1, y: 14, width: 30, height: 1.5))
                if t == .gem {
                    ctx.setFillColor(color(0x7CF7FF).cgColor)
                    ctx.addLines(between: [CGPoint(x: 16, y: 13), CGPoint(x: 21, y: 8), CGPoint(x: 16, y: 3), CGPoint(x: 11, y: 8)])
                    ctx.fillPath()
                }
            case .floor:
                gradient(ctx, r, top: 0x6B5B73, bottom: 0x3B3044)
                ctx.setFillColor(color(0x8FD16A).cgColor); ctx.fill(CGRect(x: 0, y: 13, width: 32, height: 3))
            case .ledge:
                gradient(ctx, CGRect(x: 0, y: 8, width: 32, height: 8), top: 0xC8A06A, bottom: 0x8A6436)
                ctx.setFillColor(color(0x5C3F1E).cgColor)
                ctx.fill(CGRect(x: 2, y: 0, width: 3, height: 8)); ctx.fill(CGRect(x: 27, y: 0, width: 3, height: 8))
            case .block:
                gradient(ctx, r.insetBy(dx: 0.5, dy: 0.5), top: 0xA9B4C2, bottom: 0x5D6878)
                ctx.setFillColor(color(0x2E3540).cgColor)
                for p in [CGPoint(x: 4, y: 4), CGPoint(x: 26, y: 4), CGPoint(x: 4, y: 10), CGPoint(x: 26, y: 10)] {
                    ctx.fillEllipse(in: CGRect(origin: p, size: CGSize(width: 2.5, height: 2.5)))
                }
            case .ice:
                gradient(ctx, r.insetBy(dx: 0.5, dy: 0.5), top: 0xD8F6FF, bottom: 0x6FC3E8)
                ctx.setStrokeColor(color(0xFFFFFF, 0.8).cgColor); ctx.setLineWidth(1.2)
                ctx.move(to: CGPoint(x: 5, y: 12)); ctx.addLine(to: CGPoint(x: 12, y: 5)); ctx.strokePath()
            case .quicksand:
                gradient(ctx, r, top: 0xE9C877, bottom: 0xB98D3E)
                ctx.setFillColor(color(0x8A6426, 0.6).cgColor)
                for i in 0..<9 { ctx.fillEllipse(in: CGRect(x: Double(i * 7 % 29), y: Double(i * 5 % 12), width: 2, height: 2)) }
            case .spring, .superSpring:
                let top: UInt32 = t == .spring ? 0x5CE07A : 0xFF5CC8
                ctx.setStrokeColor(color(0xC0C8D0).cgColor); ctx.setLineWidth(2)
                for i in 0..<4 { ctx.move(to: CGPoint(x: 8, y: 2 + i * 3)); ctx.addLine(to: CGPoint(x: 24, y: 3.5 + Double(i) * 3)) }
                ctx.strokePath()
                gradient(ctx, CGRect(x: 2, y: 12, width: 28, height: 4), top: top, bottom: top)
                ctx.setFillColor(color(0x3B3044).cgColor); ctx.fill(CGRect(x: 4, y: 0, width: 24, height: 2))
            case .empty:
                break
            }
        }
        tileCache[t] = tex
        return tex
    }

    /// Floor below the surface row: plain earth, no grass edge.
    static let earth = texture(32, 16) { ctx in
        gradient(ctx, CGRect(x: 0, y: 0, width: 32, height: 16), top: 0x4A3D52, bottom: 0x3B3044)
    }

    // MARK: Trolls (player sprites, 36x44 with 24x40 hitbox)

    static func troll(skin: UInt32, hair: UInt32, shirt: UInt32) -> SKTexture {
        texture(36, 44) { ctx in
            // Wild troll-doll hair: a fan of spikes sticking straight up.
            ctx.setFillColor(color(hair).cgColor)
            for i in 0..<7 {
                let a = CGFloat(i) / 6 * .pi * 0.7 + .pi * 0.15
                let tip = CGPoint(x: 18 + cos(a) * 16, y: 30 + sin(a) * 14)
                ctx.addLines(between: [CGPoint(x: 13, y: 32), tip, CGPoint(x: 23, y: 32)])
                ctx.fillPath()
            }
            // Body and feet.
            ctx.setFillColor(color(shirt).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 8, y: 6, width: 20, height: 17), cornerWidth: 7, cornerHeight: 7, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(color(0x3A2A1E).cgColor)
            ctx.fillEllipse(in: CGRect(x: 7, y: 1, width: 10, height: 6)); ctx.fillEllipse(in: CGRect(x: 19, y: 1, width: 10, height: 6))
            // Big head, ears, nose, eyes.
            ctx.setFillColor(color(skin).cgColor)
            ctx.fillEllipse(in: CGRect(x: 6, y: 18, width: 24, height: 20))
            ctx.fillEllipse(in: CGRect(x: 2, y: 25, width: 7, height: 8)); ctx.fillEllipse(in: CGRect(x: 27, y: 25, width: 7, height: 8))
            ctx.setFillColor(color(skin).blended(withFraction: 0.25, of: .black)!.cgColor)
            ctx.fillEllipse(in: CGRect(x: 20, y: 21, width: 10, height: 8))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: 14, y: 28, width: 7, height: 7)); ctx.fillEllipse(in: CGRect(x: 21, y: 28, width: 7, height: 7))
            ctx.setFillColor(color(0x1A1A2E).cgColor)
            ctx.fillEllipse(in: CGRect(x: 17, y: 30, width: 3, height: 3.5)); ctx.fillEllipse(in: CGRect(x: 24, y: 30, width: 3, height: 3.5))
        }
    }

    // MARK: Pests (drawn facing right)

    struct PestLook { var body: UInt32; var belly: UInt32; var ears: Bool; var stripes: Bool; var wings: Bool; var legs: Int }

    static func look(for kind: PestKind?) -> PestLook {
        switch kind {
        case .bulldog: return PestLook(body: 0xC7956B, belly: 0xF1D7B8, ears: true, stripes: false, wings: false, legs: 4)
        case .raccoon: return PestLook(body: 0x7D7F8C, belly: 0xD9DAE0, ears: true, stripes: true, wings: false, legs: 4)
        case .bee:     return PestLook(body: 0xF7C531, belly: 0x2B2B2B, ears: false, stripes: true, wings: true, legs: 2)
        case .spider:  return PestLook(body: 0x5B3D8C, belly: 0xB28CE8, ears: false, stripes: false, wings: false, legs: 8)
        case .raptor:  return PestLook(body: 0x58B05A, belly: 0xD3EFA5, ears: false, stripes: true, wings: false, legs: 2)
        case .cobra:   return PestLook(body: 0x3E8E7E, belly: 0xF0E08A, ears: false, stripes: false, wings: false, legs: 0)
        case nil:      return PestLook(body: 0x8C4B3A, belly: 0xE8B8A0, ears: true, stripes: false, wings: false, legs: 4)
        }
    }

    static func pest(_ kind: PestKind?, w: CGFloat, h: CGFloat, angry: Bool) -> SKTexture {
        let l = look(for: kind)
        return texture(w + 8, h + 6) { ctx in
            let bw = w, bh = h * 0.8
            let body = CGRect(x: 4, y: 5, width: bw, height: bh)
            ctx.setFillColor(color(0x1E1424).cgColor)
            for i in 0..<l.legs {
                let x = 6 + CGFloat(i) * (bw - 6) / CGFloat(max(l.legs - 1, 1))
                ctx.fill(CGRect(x: x, y: 1, width: 3, height: 6))
            }
            if l.wings {
                ctx.setFillColor(color(0xFFFFFF, 0.7).cgColor)
                ctx.fillEllipse(in: CGRect(x: bw * 0.25, y: bh, width: bw * 0.35, height: h * 0.45))
            }
            ctx.setFillColor((angry ? color(l.body).blended(withFraction: 0.45, of: .red)! : color(l.body)).cgColor)
            ctx.fillEllipse(in: body)
            if l.ears {
                ctx.fillEllipse(in: CGRect(x: bw * 0.62, y: bh * 0.9, width: 8, height: 9))
                ctx.fillEllipse(in: CGRect(x: bw * 0.80, y: bh * 0.85, width: 8, height: 9))
            }
            ctx.setFillColor(color(l.belly).cgColor)
            ctx.fillEllipse(in: CGRect(x: 4 + bw * 0.2, y: 5, width: bw * 0.55, height: bh * 0.45))
            if l.stripes {
                ctx.setFillColor(color(0x1E1424, 0.55).cgColor)
                for i in 0..<3 { ctx.fill(CGRect(x: 4 + bw * (0.2 + 0.18 * CGFloat(i)), y: 5 + bh * 0.45, width: 3, height: bh * 0.5)) }
            }
            // Eye and a grumpy brow, facing right.
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: 4 + bw * 0.68, y: 5 + bh * 0.48, width: 7, height: 7))
            ctx.setFillColor(color(0x101018).cgColor)
            ctx.fillEllipse(in: CGRect(x: 4 + bw * 0.68 + 3, y: 5 + bh * 0.48 + 1.5, width: 3.5, height: 3.5))
            ctx.setStrokeColor(color(0x101018).cgColor); ctx.setLineWidth(1.6)
            ctx.move(to: CGPoint(x: 4 + bw * 0.64, y: 5 + bh * 0.48 + 9)); ctx.addLine(to: CGPoint(x: 4 + bw * 0.68 + 8, y: 5 + bh * 0.48 + 6.5))
            ctx.strokePath()
        }
    }

    static let gem = texture(14, 14) { ctx in
        ctx.setFillColor(color(0x7CF7FF).cgColor)
        ctx.addLines(between: [CGPoint(x: 7, y: 14), CGPoint(x: 14, y: 7), CGPoint(x: 7, y: 0), CGPoint(x: 0, y: 7)])
        ctx.fillPath()
        ctx.setFillColor(color(0xFFFFFF, 0.8).cgColor)
        ctx.fill(CGRect(x: 5, y: 8, width: 3, height: 3))
    }

    // MARK: Backdrop

    /// Soft darkening toward the screen corners.
    static let vignette = texture(CGFloat(Units.screenW), CGFloat(Units.screenH)) { ctx in
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0, 0).cgColor, color(0, 0.45).cgColor] as CFArray, locations: [0.55, 1])!
        let c = CGPoint(x: Units.screenW / 2, y: Units.screenH / 2)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 420, options: .drawsAfterEndLocation)
    }

    static func backdrop(top: UInt32, bottom: UInt32) -> SKTexture {
        texture(CGFloat(Units.screenW), CGFloat(Units.screenH)) { ctx in
            gradient(ctx, CGRect(x: 0, y: 0, width: Units.screenW, height: Units.screenH), top: top, bottom: bottom)
            // Distant cavern stalactites and rocks.
            ctx.setFillColor(color(0x000000, 0.18).cgColor)
            for i in 0..<14 {
                let x = CGFloat(i) * 48 + CGFloat((i * 37) % 23)
                let len = CGFloat(20 + (i * 53) % 60)
                ctx.addLines(between: [CGPoint(x: x, y: 480), CGPoint(x: x + 22, y: 480), CGPoint(x: x + 11, y: 480 - len)])
                ctx.fillPath()
            }
            ctx.setFillColor(color(0xFFFFFF, 0.05).cgColor)
            for i in 0..<40 {
                let s = CGFloat(1 + i % 3)
                ctx.fillEllipse(in: CGRect(x: CGFloat((i * 131) % 640), y: CGFloat((i * 197) % 400) + 40, width: s, height: s))
            }
        }
    }
}
