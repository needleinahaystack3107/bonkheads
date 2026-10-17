import AVFoundation

/// Original music and sound effects, exported locally by tools/export_original.py
/// (git-ignored). Silent when the files are missing. M toggles the music.
@MainActor
final class SoundPlayer {
    private var effects: [String: [AVAudioPlayer]] = [:]   // a few voices each so sounds can overlap
    private var music: AVAudioPlayer?
    private var next: [String: Int] = [:]

    init?(folder: URL) {
        struct Manifest: Decodable { let sounds: [String: String]? }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let sounds = (try? JSONDecoder().decode(Manifest.self, from: data))?.sounds else { return nil }
        let dir = folder.appendingPathComponent("sounds")
        for (event, file) in sounds {
            let url = dir.appendingPathComponent(file)
            if event == "music" {
                music = try? AVAudioPlayer(contentsOf: url)
                music?.numberOfLoops = -1      // the original loops it from launch
                music?.volume = 0.45
            } else {
                effects[event] = (0..<3).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
                effects[event]?.forEach { $0.prepareToPlay() }
            }
        }
    }

    func play(_ event: String) {
        guard let voices = effects[event], !voices.isEmpty else { return }
        let i = next[event, default: 0]
        next[event] = (i + 1) % voices.count
        voices[i].currentTime = 0
        voices[i].play()
    }

    func startMusic() { music?.play() }

    func toggleMusic() {
        guard let music else { return }
        if music.isPlaying { music.pause() } else { music.play() }
    }
}
