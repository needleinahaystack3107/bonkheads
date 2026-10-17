import AppKit
import SpriteKit

/// Optional original sprites, exported locally from the user's own copy of the
/// demo by tools/export_original.py (git-ignored, never shipped). When the
/// folder is missing the game falls back to the placeholder art in Art.swift.
@MainActor
final class OriginalArt {
    /// actor -> animation -> frames, e.g. ["bulldog"]["stunned"]
    private let actors: [String: [String: [SKTexture]]]

    init?(folder: URL) {
        struct Manifest: Decodable { let actors: [String: [String: [String]]] }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        let art = folder.appendingPathComponent("art")
        actors = manifest.actors.mapValues { anims in
            anims.mapValues { files in
                files.compactMap { file in
                    NSImage(contentsOf: art.appendingPathComponent(file)).map { image in
                        let t = SKTexture(image: image)
                        t.filteringMode = .nearest   // keep the 2003 pixel art crisp
                        return t
                    }
                }
            }
        }
    }

    func has(_ actor: String) -> Bool { actors[actor] != nil }

    /// Frame `step` of an animation, looping; nil if the actor or animation is missing.
    func frame(_ actor: String, _ anim: String, step: Int) -> SKTexture? {
        guard let frames = actors[actor]?[anim], !frames.isEmpty else { return nil }
        return frames[((step % frames.count) + frames.count) % frames.count]
    }
}
