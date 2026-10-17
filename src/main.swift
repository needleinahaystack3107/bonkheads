import AppKit
import SpriteKit

// Entry point.
//   Bonkheads                    play (levels from ./levels or $BONKHEADS_LEVELS)
//   Bonkheads --validate [files] check level files and report problems
//   Bonkheads --autoplay         a computer player plays player 1 (demo)
//   Bonkheads --screenshot out.png [--after seconds]
//                                autoplay, save the game's own frame, quit
//                                (--show menu|levels to capture a menu instead)

/// Finds a project folder: the working directory, then any parent of the
/// executable (so `.build/release/Bonkheads` finds the repo's folders).
func projectFolder(_ name: String) -> URL {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: cwd.path) { return cwd }
    var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    while dir.path != "/" {
        let candidate = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        dir.deleteLastPathComponent()
    }
    return cwd
}

/// levels/, or $BONKHEADS_LEVELS to play a different folder.
func levelsFolder() -> URL {
    ProcessInfo.processInfo.environment["BONKHEADS_LEVELS"].map(URL.init(fileURLWithPath:)) ?? projectFolder("levels")
}

func validate(_ paths: [String]) -> Int32 {
    let results = paths.isEmpty
        ? Level.loadAll(in: levelsFolder())
        : paths.map { p in (URL(fileURLWithPath: p), Result { try Level.load(URL(fileURLWithPath: p)) }) }
    if results.isEmpty { print("no level files found"); return 1 }
    var failures: Int32 = 0
    for (url, result) in results {
        switch result {
        case .success(let level):
            print("ok    \(url.lastPathComponent)  \"\(level.name)\": \(level.spawns.count) pests\(level.boss != nil ? " + boss" : "")")
        case .failure(let error):
            print("error \(url.lastPathComponent): \(error)")
            failures += 1
        }
    }
    return failures == 0 ? 0 : 1
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        let results = Level.loadAll(in: levelsFolder())
        let levels = results.compactMap { try? $0.result.get() }
        let errors = results.compactMap { r -> String? in
            if case .failure(let e) = r.result { return "\(r.url.lastPathComponent): \(e)" }
            return nil
        }

        let view = SKView(frame: NSRect(x: 0, y: 0, width: 1280, height: 960))
        view.preferredFramesPerSecond = 120
        view.ignoresSiblingOrder = true
        let scene = GameScene(levels: levels, loadErrors: errors)
        // Original sprites from tools/export_original.py, unless --placeholder-art.
        if !CommandLine.arguments.contains("--placeholder-art") {
            scene.originalArt = OriginalArt(folder: projectFolder("local-original"))
            if !CommandLine.arguments.contains("--screenshot") { scene.sound = SoundPlayer(folder: projectFolder("local-original")) }
            scene.sound?.startMusic()
        }
        view.presentScene(scene)
        configureDebugOptions(scene, view: view)

        window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Bonkheads"
        window.contentView = view
        window.contentAspectRatio = NSSize(width: 4, height: 3)
        window.collectionBehavior = .fullScreenPrimary
        window.center()
        installMenuBar()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view.scene)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Standard Mac menu bar so ⌘Q quits and ⌃⌘F toggles full screen.
    private func installMenuBar() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        bar.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Bonkheads", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let viewItem = NSMenuItem()
        bar.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        let full = viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = viewMenu
        NSApp.mainMenu = bar
    }

    private func configureDebugOptions(_ scene: GameScene, view: SKView) {
        let args = CommandLine.arguments
        guard args.contains("--autoplay") || args.contains("--screenshot") else { return }
        // --show menu|levels screenshots a menu instead of autoplaying level 1.
        switch args.firstIndex(of: "--show").map({ args[$0 + 1] }) {
        case "menu": break
        case "levels": scene.showLevelSelect()
        default:
            scene.autoplay = true
            scene.start(players: 1)
        }
        guard let i = args.firstIndex(of: "--screenshot"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        let after = args.firstIndex(of: "--after").flatMap { Double(args[$0 + 1]) } ?? 8
        // Step the scene by hand (60 Hz) so this works even if the window is
        // hidden, then render the scene ourselves: no screen-recording permission needed.
        DispatchQueue.main.async {
            for frame in 0...Int(after * 60) { scene.update(Double(frame) / 60) }
            if let cg = view.texture(from: scene)?.cgImage(),
               let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: out)
                print("saved \(out.path)")
            }
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

/// Headless check: the autopilot plays the first level; prints what happened.
func simulate(seconds: Double) -> Int32 {
    guard let level = Level.loadAll(in: levelsFolder()).compactMap({ try? $0.result.get() }).first else { return 1 }
    let game = Game(level: level, playerCount: 1)
    var counts: [String: Int] = [:]
    for _ in 0..<Units.ticks(seconds: seconds) {
        game.step(inputs: [Autopilot.input(for: game.players[0], in: game)])
        for e in game.events { counts[String(describing: e).prefix(while: { $0 != "(" }).description, default: 0] += 1 }
        if game.isCleared || game.isOver { break }
    }
    print("tick \(game.tick) cleared \(game.isCleared) over \(game.isOver) score \(game.players[0].score) lives \(game.players[0].lives)")
    print("events", counts.sorted { $0.key < $1.key })
    for p in game.pests { print("pest", p.kind?.rawValue ?? "boss", "at", p.body.left, p.body.top, "flipped", p.flipped, "vx", p.body.vx) }
    return 0
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--validate" {
    exit(validate(Array(args.dropFirst())))
}
if args.first == "--simulate" {
    exit(simulate(seconds: args.count > 1 ? Double(args[1]) ?? 30 : 30))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
