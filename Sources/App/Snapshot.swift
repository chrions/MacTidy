import AppKit

/// Development aid: `open MacTidy.app --args -snapshot /tmp/a.png [-page 应用] [-shelf ID] [-unused YES]`
/// renders the window into a PNG, which works without Screen Recording permission.
enum Snapshot {
    @MainActor
    static func runIfRequested(_ model: AppModel) async {
        let d = UserDefaults.standard
        guard let path = d.string(forKey: "snapshot") else { return }
        if let page = d.string(forKey: "page") {
            if page == "冷藏区" { model.sidebar = .coldRoom } else if let c = Category(rawValue: page) { model.sidebar = .category(c) }
        }
        if let shelf = d.string(forKey: "shelf") { model.selectedShelf = shelf }
        if d.bool(forKey: "unused") { model.onlyUnused = true }
        if d.bool(forKey: "ai"), let s = model.shelf(model.selectedShelf) {
            model.recognise([s], force: true)
            for _ in 0..<60 where model.aiProgress != nil { try? await Task.sleep(for: .milliseconds(500)) }
        }
        try? await Task.sleep(for: .seconds(2))
        guard let window = NSApp.windows.first(where: \.isVisible), let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
