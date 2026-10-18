import AppKit
import CoreServices

struct AppInfo {
    let name: String
    let bundleID: String?
    let path: String
    let version: String?
    let lastUsed: Date?
    let useCount: Int?
    let isAppStore: Bool

    var isApple: Bool { bundleID?.hasPrefix("com.apple.") ?? false }
}

/// What is installed: apps (with Spotlight usage) and commands on the login shell's PATH.
final class Inventory {
    let apps: [AppInfo]
    let systemApps: [AppInfo]
    let pathDirs: [String]
    let missingPathDirs: [String]
    let commands: [String: String]
    private let bundleIDs: [String]

    init(home: String) {
        apps = (Inventory.findApps(in: ["/Applications", home + "/Applications"])).sorted { $0.name < $1.name }
        systemApps = Inventory.findApps(in: ["/System/Applications", "/System/Library/CoreServices"])
        bundleIDs = (apps + systemApps).compactMap { $0.bundleID?.lowercased() }

        let rawPath = Inventory.loginPath(home: home)
        pathDirs = rawPath.filter(isDirectory)
        // cryptexd bootstrap paths are injected by sandboxed hosts (e.g. editor agents), not user config.
        missingPathDirs = rawPath.filter { !exists($0) && !$0.hasPrefix("/var/run/com.apple.security.cryptexd/") }
        var cmds = [String: String]()
        for dir in pathDirs {
            for name in children(dir) where cmds[name] == nil {
                let full = (dir as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: full) { cmds[name] = full }
            }
        }
        commands = cmds
    }

    /// App whose name or bundle ID contains any keyword (case-insensitive).
    func findApp(_ keywords: [String]) -> AppInfo? {
        let keys = keywords.map { $0.lowercased() }
        return (apps + systemApps).first { app in
            let hay = [app.name.lowercased(), app.bundleID?.lowercased() ?? ""]
            return keys.contains { k in hay.contains { $0.contains(k) } }
        }
    }

    func findCommand(_ names: [String]) -> String? {
        names.lazy.compactMap { self.commands[$0] }.first
    }

    /// Installed app matching a reverse-DNS identifier exactly, by prefix, or via LaunchServices.
    func owner(ofBundleID id: String) -> String? {
        let lower = id.lowercased()
        if let app = (apps + systemApps).first(where: {
            guard let b = $0.bundleID?.lowercased() else { return false }
            return b == lower || lower.hasPrefix(b + ".") || b.hasPrefix(lower + ".")
        }) {
            return app.name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), exists(url.path) {
            return url.deletingPathExtension().lastPathComponent
        }
        if let last = lower.split(separator: ".").last, last.count >= 3, commands[String(last)] != nil {
            return "命令 \(last)"
        }
        return nil
    }

    /// Same vendor prefix (e.g. `com.tencent`) as some installed app.
    func vendorMatch(ofBundleID id: String) -> String? {
        let parts = id.lowercased().split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let vendor = parts.prefix(2).joined(separator: ".") + "."
        return (apps + systemApps).first { $0.bundleID?.lowercased().hasPrefix(vendor) ?? false }?.name
    }

    /// Owner for a plain folder name like "Google" or "Code": an app, a command, or nothing.
    func owner(ofName name: String) -> String? {
        let lower = name.lowercased()
        guard lower.count >= 3 else { return nil }
        if let app = (apps + systemApps).first(where: { app in
            let n = app.name.lowercased()
            let b = app.bundleID?.lowercased() ?? ""
            return n == lower || n.contains(lower) || lower.contains(n) || b.split(separator: ".").contains { $0 == lower }
        }) {
            return app.name
        }
        if commands[lower] != nil || commands[name] != nil { return "命令 \(name)" }
        return nil
    }

    private static func findApps(in roots: [String]) -> [AppInfo] {
        var result = [AppInfo]()
        for root in roots {
            for entry in children(root) {
                let path = (root as NSString).appendingPathComponent(entry)
                if entry.hasSuffix(".app") {
                    result.append(appInfo(path))
                } else if isDirectory(path), !isSymlink(path) {
                    for sub in children(path) where sub.hasSuffix(".app") {
                        result.append(appInfo((path as NSString).appendingPathComponent(sub)))
                    }
                }
            }
        }
        return result
    }

    private static func appInfo(_ path: String) -> AppInfo {
        let bundle = Bundle(path: path)
        let info = bundle?.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var lastUsed: Date?
        var useCount: Int?
        if let md = MDItemCreate(kCFAllocatorDefault, path as CFString) {
            lastUsed = MDItemCopyAttribute(md, kMDItemLastUsedDate) as? Date
            useCount = (MDItemCopyAttribute(md, "kMDItemUseCount" as CFString) as? NSNumber)?.intValue
        }
        return AppInfo(name: name, bundleID: bundle?.bundleIdentifier, path: path,
                       version: info["CFBundleShortVersionString"] as? String,
                       lastUsed: lastUsed, useCount: useCount,
                       isAppStore: exists(path + "/Contents/_MASReceipt/receipt"))
    }

    /// PATH as seen by an interactive login zsh, so nvm/rbenv/brew additions in .zshrc count.
    private static func loginPath(home: String) -> [String] {
        let out = NSTemporaryDirectory() + "mactidy-path-\(getpid())"
        // +m: no job control, otherwise the interactive shell takes over the terminal and suspends us.
        run("/bin/zsh", ["+m", "-lic", "print -r -- \"$PATH\" > '\(out)'"], env: ["DISABLE_AUTO_UPDATE": "true"], timeout: 20)
        defer { try? fm.removeItem(atPath: out) }
        let raw = readText(out) ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        var seen = Set<String>()
        return raw.split(separator: ":").map(String.init).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
