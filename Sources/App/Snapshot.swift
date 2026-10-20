import AppKit
import SwiftUI

/// Development aid: `open MacTidy.app --args -snapshot /tmp/a.png [-page 应用] [-shelf ID] [-unused YES]`
/// renders the window into a PNG, which works without Screen Recording permission.
enum Snapshot {
    @MainActor
    static func runIfRequested(_ model: AppModel, openSettings: OpenSettingsAction) async {
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
        let settings = d.bool(forKey: "settings")
        if settings {
            try? await Task.sleep(for: .seconds(1))
            openSettings()
        }
        try? await Task.sleep(for: .seconds(2))
        let windows = NSApp.windows.filter(\.isVisible)
        guard let window = settings ? windows.first(where: { $0.identifier?.rawValue.contains("Settings") == true || $0.title.contains("设置") }) : windows.first,
              let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
