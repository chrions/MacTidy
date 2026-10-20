import AppKit
import SwiftUI

/// Development aid: `open MacTidy.app --args -snapshot /tmp/a.png [-page 应用] [-shelf ID] [-unused YES]`
/// renders the window into a PNG, which works without Screen Recording permission.
enum Snapshot {
    @MainActor
    static func runIfRequested(_ model: AppModel, openSettings: OpenSettingsAction) async {
        let d = UserDefaults.standard
        if let out = d.string(forKey: "aitest") {
            let client = AIClient(config: model.aiConfig, key: AIKey.read(for: model.aiConfig.baseURL))
            var lines = ["key 长度：\(AIKey.read(for: model.aiConfig.baseURL)?.count ?? 0)"]
            do { lines.append("测试连接：成功 " + (try await client.test())) } catch { lines.append("测试连接：" + error.localizedDescription) }
            do {
                let s = AISubject(id: "1", title: "com.tencent.wwmapp", category: "无主之物", summary: "", paths: ["~/Library/Containers/com.tencent.wwmapp"],
                                  kinds: ["沙盒数据"], size: "229 MB", cameFrom: "", lastActive: "", usedSinceArrival: "")
                lines.append("识别：" + ((try await client.recognise([s]))["1"]?.what ?? "没有结果"))
            } catch { lines.append("识别：" + error.localizedDescription) }
            try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            return
        }
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
