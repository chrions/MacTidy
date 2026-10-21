import AppKit
import SwiftUI

/// Development aid: `open MacTidy.app --args -snapshot /tmp/a.png [-page apps|cold] [-shelf ID] [-unused YES] [-size 1280x800] [-AppleLanguages '(ja)']`
/// renders the window into a PNG, which works without Screen Recording permission.
enum Snapshot {
    @MainActor
    static func runIfRequested(_ model: AppModel, openSettings: OpenSettingsAction) async {
        let d = UserDefaults.standard
        if let out = d.string(forKey: "aitest") {
            let client = AIClient(config: model.aiConfig, key: AIKey.read(for: model.aiConfig.baseURL))
            var lines = ["key length: \(AIKey.read(for: model.aiConfig.baseURL)?.count ?? 0)"]
            do { lines.append("test: ok " + (try await client.test())) } catch { lines.append("test: " + error.localizedDescription) }
            do {
                let s = AISubject(id: "1", title: "com.tencent.wwmapp", category: Category.orphans.name, summary: "",
                                  paths: ["~/Library/Containers/com.tencent.wwmapp"], kinds: [BookKind.sandbox.name], size: "229 MB",
                                  cameFrom: "", lastActive: "", usedSinceArrival: "")
                let note = try await client.recognise([s])["1"]
                lines.append("recognise: " + (note.map { [$0.owner, $0.what, $0.advice, $0.reason].compactMap { $0 }.joined(separator: " | ") } ?? "no result"))
            } catch { lines.append("recognise: " + error.localizedDescription) }
            try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            return
        }
        if let shelfID = d.string(forKey: "demo") {
            await demo(model, shelfID: shelfID)
            return
        }
        guard let path = d.string(forKey: "snapshot") else { return }
        for _ in 0..<600 where model.scanning { try? await Task.sleep(for: .milliseconds(500)) }
        if let page = d.string(forKey: "page") {
            if page == "cold" { model.sidebar = .coldRoom } else if let c = Category(rawValue: page) { model.sidebar = .category(c) }
        }
        if let shelf = d.string(forKey: "shelf") { model.selectedShelf = shelf }
        if d.bool(forKey: "unused") { model.onlyUnused = true }
        if d.bool(forKey: "ai"), let s = model.shelf(model.selectedShelf) {
            model.recognise([s], force: true)
            for _ in 0..<60 where model.aiProgress != nil { try? await Task.sleep(for: .milliseconds(500)) }
        }
        let settings = d.bool(forKey: "settings")
        if settings {
            try? await Task.sleep(for: .seconds(1))
            openSettings()
        }
        if let size = d.string(forKey: "size")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            NSApp.windows.first(where: \.isVisible)?.setContentSize(NSSize(width: size[0], height: size[1]))
        }
        try? await Task.sleep(for: .seconds(2))
        let windows = NSApp.windows.filter(\.isVisible)
        guard let window = settings ? windows.first(where: { $0.identifier?.rawValue.contains("Settings") == true }) : windows.first,
              let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// `-demo SHELF_ID` plays a scripted walkthrough for a screen recording, in full screen: freeze the
    /// shelf's first unused item, put it back from cold storage, and return to the shelf. It touches
    /// /tmp/mactidy-demo-ready once in full screen, waits for /tmp/mactidy-demo-go, touches
    /// /tmp/mactidy-demo-done at the end, then leaves full screen.
    @MainActor
    private static func demo(_ model: AppModel, shelfID: String) async {
        func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        let fm = FileManager.default
        for _ in 0..<600 where model.scanning { await pause(0.5) }
        await pause(1)
        guard let window = NSApp.windows.first(where: \.isVisible), let shelf = model.shelf(shelfID),
              let book = model.movable(shelf, onlyUnused: true).first else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.onlyUnused = false
        model.sidebar = .category(shelf.category)
        model.selectedShelf = shelf.id
        if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        await pause(2.5)
        fm.createFile(atPath: "/tmp/mactidy-demo-ready", contents: nil)

        while !fm.fileExists(atPath: "/tmp/mactidy-demo-go") { await pause(0.2) }
        await pause(2.5)
        model.request(.freeze, [book], in: shelf)
        await pause(3)
        model.confirm()
        await pause(3)
        guard case .freeze(let batch)? = model.outcome?.undo else { return }
        model.sidebar = .coldRoom
        await pause(3)
        model.thaw(batch)
        await pause(3)
        model.sidebar = .category(shelf.category)
        model.selectedShelf = shelf.id
        await pause(3.5)
        fm.createFile(atPath: "/tmp/mactidy-demo-done", contents: nil)
        await pause(1)
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }
}
