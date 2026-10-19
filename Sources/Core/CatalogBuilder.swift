import AppKit

/// Builds the library catalog: every item finds an owner, and each owner gets a shelf.
final class CatalogBuilder {
    let ctx: Context
    let eras: [Era]
    var inv: Inventory { ctx.inventory }
    var home: String { ctx.home }

    private(set) var shelves = [String: Shelf]()
    private var order = [String]()
    private var appShelfIDs = [String: String]()
    private var placed = Set<String>()
    var orphanPool = [OrphanEntry]()

    struct OrphanEntry {
        var id: String
        var isBundleID: Bool
        var alias: String?
        var note: String?
        var book: Book
    }

    enum Owner {
        case app(AppInfo)
        case apple
        case tool(String)
        case command(String)
        case orphan(alias: String?, note: String?)
    }

    init(ctx: Context) {
        self.ctx = ctx
        eras = Eras.detect(home: ctx.home)
    }

    func build(progress: (String) -> Void) -> Catalog {
        progress("应用"); addApps()
        progress("资源库（~/Library 和 /Library）"); addLibrary()
        progress("开机服务"); addLaunchItems()
        progress("开发环境"); addDevEnvironments()
        progress("终端与命令"); addTerminal()
        progress("个人文件"); addPersonal()
        addSystem()
        groupOrphans()
        progress("统计大小和时间"); measure()
        finalize()
        foldTinyOrphans()
        return Catalog(generatedAt: ctx.now, machine: Eras.machineDescription(), eras: eras,
                       shelves: order.compactMap { shelves[$0] }.filter { !$0.books.isEmpty }, notes: notes)
    }

    var notes: [String] {
        [
            "年代按每台 Mac 在 ~/Library/Keychains 留下的机器文件夹的创建时间推断；一样东西的年代取它最早那个文件的创建时间。",
            "「搬来后用过」看的是应用的 Spotlight 打开记录和数据目录的修改时间；被其他程序在后台调用的东西可能显示为没用过。",
            "苹果自带的东西归在「系统」，只做说明，不建议改动。",
        ]
    }

    // MARK: Shelf helpers

    @discardableResult
    func shelf(_ id: String, _ category: Category, _ title: String, _ summary: String) -> String {
        if shelves[id] == nil {
            shelves[id] = Shelf(id: id, category: category, title: title, summary: summary)
            order.append(id)
        }
        return id
    }

    /// First placement wins: a path found by several scanners stays on one shelf.
    func add(_ book: Book, to id: String) {
        guard shelves[id] != nil, placed.insert(book.path).inserted else { return }
        shelves[id]!.books.append(book)
    }

    func update(_ id: String, _ body: (inout Shelf) -> Void) {
        guard shelves[id] != nil else { return }
        body(&shelves[id]!)
    }

    func book(_ path: String, _ kind: BookKind, note: String? = nil, size: Int64? = nil) -> Book {
        let parent = (path as NSString).deletingLastPathComponent
        return Book(path: path, kind: kind, size: size, created: creationDate(path), note: note,
                    protected: !fm.isWritableFile(atPath: parent))
    }

    // MARK: Apps

    func appShelfID(_ app: AppInfo) -> String { appShelfIDs[app.path] ?? "app:" + (app.bundleID ?? app.path) }

    private func addApps() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path })
        for app in inv.apps {
            let info = Bundle(path: app.path)?.infoDictionary ?? [:]
            let system = app.isApple && !app.isAppStore
            let id = shelf("app:" + (app.bundleID ?? app.path), system ? .system : .apps, app.name, appSummary(app, info: info))
            appShelfIDs[app.path] = id
            var flags = [String]()
            if let v = app.version { flags.append("版本 \(v)") }
            if app.isAppStore { flags.append("App Store") }
            if running.contains(URL(fileURLWithPath: app.path).standardizedFileURL.path) { flags.append("正在运行") }
            if let arch = archFlag(app.path) { flags.append(arch) }
            if let n = app.useCount { flags.append("打开过 \(n) 次") }
            update(id) {
                $0.lastUsed = app.lastUsed
                $0.lastUsedSource = "Spotlight 打开记录"
                $0.flags = flags
            }
            add(book(app.path, .program), to: id)
        }
    }

    private func appSummary(_ app: AppInfo, info: [String: Any]) -> String {
        let kind = (info["LSApplicationCategoryType"] as? String).flatMap { appCategoryNames[$0] }
        let vendor = (info["NSHumanReadableCopyright"] as? String).flatMap(vendorName)
        let parts = [kind, vendor.map { "出自 \($0)" }].compactMap { $0 }
        return parts.isEmpty ? "应用" : parts.joined(separator: "，")
    }

    /// "Copyright © 2012-2024 Tencent. All Rights Reserved." → "Tencent"
    private func vendorName(_ copyright: String) -> String? {
        var s = copyright.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.replacingOccurrences(of: #"(?i)copyright|©|\(c\)|all rights reserved\.?|版权所有|[0-9]{4}(\s*[-–]\s*[0-9]{4})?"#,
                                               with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " .,，。").union(.whitespacesAndNewlines))
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.count >= 2 && s.count <= 40 ? s : nil
    }

    private func archFlag(_ path: String) -> String? {
        guard let archs = Bundle(path: path)?.executableArchitectures?.map(\.intValue), !archs.isEmpty else { return nil }
        let arm = archs.contains(NSBundleExecutableArchitectureARM64)
        let intel = archs.contains(NSBundleExecutableArchitectureX86_64)
        return intel && !arm ? "仅 Intel（靠 Rosetta 转译运行）" : nil
    }

    // MARK: ~/Library and /Library

    private func addLibrary() {
        let user: [(String, BookKind)] = [
            ("Application Support", .userData), ("Containers", .sandbox), ("Group Containers", .shared), ("Caches", .cache),
            ("Preferences", .preferences), ("Logs", .logs), ("Saved Application State", .windowState),
            ("HTTPStorages", .webData), ("WebKit", .webData), ("Cookies", .webData),
            ("Internet Plug-Ins", .plugin), ("PreferencePanes", .plugin), ("Services", .plugin), ("QuickLook", .plugin),
            ("Input Methods", .plugin), ("Screen Savers", .plugin), ("Audio/Plug-Ins/Components", .plugin),
            ("Audio/Plug-Ins/HAL", .plugin),
        ]
        let shared: [(String, BookKind)] = [
            ("Application Support", .userData), ("Caches", .cache), ("Preferences", .preferences),
            ("PrivilegedHelperTools", .helper), ("Internet Plug-Ins", .plugin), ("PreferencePanes", .plugin),
            ("Input Methods", .plugin), ("Screen Savers", .plugin), ("QuickLook", .plugin), ("Extensions", .plugin),
            ("Audio/Plug-Ins/HAL", .plugin), ("Audio/Plug-Ins/Components", .plugin),
        ]
        for (rel, kind) in user { scanLocation(home + "/Library/" + rel, kind: kind, sharedNote: nil) }
        for (rel, kind) in shared { scanLocation("/Library/" + rel, kind: kind, sharedNote: "所有用户共用，删除需要管理员权限") }
    }

    private func scanLocation(_ dir: String, kind: BookKind, sharedNote: String?) {
        let location = (dir as NSString).lastPathComponent
        for entry in children(dir) where !entry.hasPrefix(".") {
            let path = dir + "/" + entry
            let id = normalizedID(entry, location: location)
            if location == "Caches", toolCaches[entry] != nil || entry == "Homebrew" {
                if let tool = toolchain(named: entry) {
                    add(book(path, .cache, note: toolCaches[entry]), to: toolShelf(tool))
                    continue
                }
            }
            place(book(path, kind, note: sharedNote), id: id, entry: entry)
        }
    }

    /// Puts a book on its owner's shelf.
    func place(_ b: Book, id: String, entry: String, note: String? = nil) {
        switch resolve(id: id, entry: entry, kind: b.kind) {
        case .app(let app):
            add(b, to: appShelfID(app))
        case .apple:
            add(b, to: appleShelf(for: b.kind))
        case .tool(let t):
            add(b, to: toolShelf(t))
        case .command(let c):
            add(b, to: shelf("cmd:" + c, .terminal, "\(c)（命令行工具）", "命令 \(c) 的数据和配置"))
        case .orphan(let alias, let n):
            orphanPool.append(OrphanEntry(id: id, isBundleID: looksLikeBundleID(id), alias: alias, note: n ?? note, book: b))
        }
    }

    func normalizedID(_ entry: String, location: String) -> String {
        var id = entry
        for ext in [".plist", ".savedState", ".binarycookies", ".log"] where id.hasSuffix(ext) {
            id = String(id.dropLast(ext.count))
        }
        if id.hasPrefix("group.") { id = String(id.dropFirst(6)) }
        if let r = id.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) { id = String(id[r.upperBound...]) }
        if id.hasPrefix("group.") { id = String(id.dropFirst(6)) }
        return id
    }

    func looksLikeBundleID(_ id: String) -> Bool {
        id.split(separator: ".").count >= 3 && !id.contains(" ")
    }

    func isApple(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower.contains("com.apple") || lower.hasPrefix("apple") || appleLibraryNames.contains(id)
            || lower.hasPrefix("systemgroup.") || lower == "loginwindow" || lower.hasPrefix("pbs")
            || id.range(of: #"^[a-z]+d$"#, options: .regularExpression) != nil
    }

    func resolve(id: String, entry: String, kind: BookKind) -> Owner {
        if looksLikeBundleID(id), let app = appForBundleID(id) { return .app(app) }
        if isApple(id) { return .apple }
        let lower = id.lowercased()
        if let tool = toolchain(named: entry) ?? toolchain(named: id) { return .tool(tool) }
        if let alias = libraryAlias(for: id) {
            if alias.owner.hasPrefix("macOS") { return .apple }
            if let app = findApp(alias.apps) { return .app(app) }
            if let cmd = alias.commands.first(where: { inv.commands[$0] != nil }) {
                return toolchain(named: cmd).map(Owner.tool) ?? .command(cmd)
            }
            return .orphan(alias: alias.owner, note: nil)
        }
        if looksLikeBundleID(id) {
            if let app = appForBundleID(id) { return .app(app) }
            if let (app, sameProduct) = vendorApp(id) {
                // A vendor's only app owns its privileged helpers and launch services (com.docker.vmnetd).
                let helperWords = ["keystone", "update", "helper", "agent", "launcher", "daemon", "crashpad", "installer", "ksfetch"]
                let looksHelper = [.helper, .launch].contains(kind) || helperWords.contains { lower.contains($0) }
                if sameProduct || (looksHelper && vendorAppCount(id) == 1) { return .app(app) }
                return .orphan(alias: nil, note: "同厂商的 \(app.name) 还装着，但这个看起来是另一款产品")
            }
            if let last = lower.split(separator: ".").last, last.count >= 3, let cmd = userCommand(String(last)) {
                return toolchain(named: cmd).map(Owner.tool) ?? .command(cmd)
            }
            return .orphan(alias: nil, note: nil)
        }
        if let app = appForName(id) { return .app(app) }
        if id.count >= 3, let cmd = userCommand(id) ?? userCommand(lower) {
            return toolchain(named: cmd).map(Owner.tool) ?? .command(cmd)
        }
        if id.count >= 3, inv.commands[id] != nil || inv.commands[lower] != nil { return .apple }
        return .orphan(alias: nil, note: nil)
    }

    /// A command on PATH that is not part of macOS (/usr/bin, /bin, ...).
    private func userCommand(_ name: String) -> String? {
        guard let path = inv.commands[name] else { return nil }
        let system = ["/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/", "/System/", "/usr/libexec/", "/Library/Apple/"]
        return system.contains(where: path.hasPrefix) ? nil : name
    }

    private func findApp(_ keywords: [String]) -> AppInfo? {
        guard !keywords.isEmpty, let found = inv.findApp(keywords) else { return nil }
        return inv.apps.first { $0.path == found.path }
    }

    private func appForBundleID(_ id: String) -> AppInfo? {
        let lower = id.lowercased()
        return inv.apps.first {
            guard let b = $0.bundleID?.lowercased() else { return false }
            return b == lower || lower.hasPrefix(b + ".") || b.hasPrefix(lower + ".") || b.hasPrefix(lower + "-")
        }
    }

    private func vendorApps(_ id: String) -> [AppInfo] {
        let parts = id.lowercased().split(separator: ".")
        guard parts.count >= 3 else { return [] }
        let vendor = parts.prefix(2).joined(separator: ".") + "."
        return inv.apps.filter { $0.bundleID?.lowercased().hasPrefix(vendor) ?? false }
    }

    private func vendorAppCount(_ id: String) -> Int { vendorApps(id).count }

    /// An installed app from the same vendor (`com.tencent.*`). `sameProduct` when the product names share a stem,
    /// e.g. com.tencent.WeWork-Helper and com.tencent.WeWorkMac.
    private func vendorApp(_ id: String) -> (AppInfo, sameProduct: Bool)? {
        let same = vendorApps(id)
        guard let first = same.first else { return nil }
        func product(_ s: String) -> String {
            let p = s.lowercased().split(separator: ".")
            return p.count >= 3 ? String(p[2]).filter { $0.isLetter || $0.isNumber } : ""
        }
        let mine = product(id)
        for app in same {
            let theirs = product(app.bundleID ?? "")
            let common = zip(mine, theirs).prefix { $0 == $1 }.count
            if !mine.isEmpty, mine == theirs || common >= 5 { return (app, true) }
        }
        return (first, false)
    }

    private func appForName(_ name: String) -> AppInfo? {
        let lower = name.lowercased()
        guard lower.count >= 3 else { return nil }
        return inv.apps.first { app in
            let n = app.name.lowercased()
            let b = app.bundleID?.lowercased() ?? ""
            return n == lower || (lower.count >= 4 && (n.contains(lower) || lower.contains(n)))
                || b.split(separator: ".").contains { $0 == lower }
        }
    }

    // MARK: Launch agents / daemons

    private func addLaunchItems() {
        let items = Scanners(ctx: ctx).launchItems()
        for item in items {
            guard let path = item.path else { continue }
            let note = [item.detail, item.verdict == .keep ? nil : item.reason].compactMap { $0 }.joined(separator: "；")
            let b = book(path, .launch, note: note, size: 0)
            if let owner = item.owner, let app = inv.apps.first(where: { $0.name == owner }) {
                add(b, to: appShelfID(app))
            } else {
                let label = String((path as NSString).lastPathComponent.dropLast(6))
                place(b, id: label, entry: label, note: item.reason)
            }
        }
    }

    // MARK: System

    private func appleShelf(for kind: BookKind) -> String {
        switch kind {
        case .cache, .logs, .windowState, .webData:
            return shelf("apple:cache", .system, "系统和自带应用的缓存与日志", "macOS 自动生成和清理，不需要手动处理")
        case .preferences:
            return shelf("apple:prefs", .system, "系统和自带应用的设置", "系统设置、访达、程序坞等的偏好设置")
        default:
            return shelf("apple:data", .system, "系统和自带应用的数据", "照片、信息、邮件、iCloud 等苹果自带功能的数据")
        }
    }

    private func addSystem() {
        let core = shelf("apple:core", .system, "macOS 系统本体", "装在只读、带加密签名的系统盘上，任何人（包括 root）都改不了")
        for p in ["/System", "/bin", "/sbin", "/usr", "/private/etc"] {
            add(Book(path: p, kind: .program, size: nil, created: nil, note: nil, protected: true), to: core)
        }
        let apps = shelf("apple:apps", .system, "macOS 自带应用", "\(inv.systemApps.count) 个苹果自带应用，随系统更新")
        add(Book(path: "/System/Applications", kind: .program, size: nil, created: nil, note: nil, protected: true), to: apps)
        let vm = shelf("apple:vm", .system, "虚拟内存和系统临时文件", "系统运行时自动管理")
        add(Book(path: "/private/var", kind: .cache, size: nil, created: nil, note: "系统日志、临时文件、虚拟内存交换文件", protected: true), to: vm)
    }

    // MARK: Orphans

    /// Leftovers whose owner is gone: an app's helpers and extensions (com.vendor.app.*) collapse into one shelf.
    private func groupOrphans() {
        func key(_ e: OrphanEntry) -> String {
            e.isBundleID ? e.id.lowercased().split(separator: ".").prefix(3).joined(separator: ".") : e.id.lowercased()
        }
        var groups = [String: [OrphanEntry]]()
        var keys = [String]()
        for e in orphanPool {
            let k = e.alias.map { "alias:" + $0 } ?? key(e)
            if groups[k] == nil { keys.append(k) }
            groups[k, default: []].append(e)
        }
        for k in keys.sorted(by: { $0.count < $1.count }) where groups[k] != nil {
            for other in keys where other != k && other.hasPrefix(k + ".") {
                if let g = groups.removeValue(forKey: other) { groups[k]! += g }
            }
        }
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let bundleKeys = keys.filter { groups[$0]?.first?.isBundleID == true }
        for k in keys where groups[k]?.first?.isBundleID == false && !k.hasPrefix("alias:") {
            let n = norm(k)
            guard n.count >= 4 else { continue }
            let target = bundleKeys.first { bk in
                bk.split(separator: ".").dropFirst(2).contains { comp in
                    let c = norm(String(comp))
                    return c.count >= 4 && (c == n || c.hasPrefix(n) || n.hasPrefix(c))
                }
            }
            if let target, groups[target] != nil, let g = groups.removeValue(forKey: k) { groups[target]! += g }
        }
        for k in keys {
            guard let entries = groups[k] else { continue }
            let first = entries[0]
            let title = first.alias ?? (first.isBundleID ? entries.map(\.id).min(by: { $0.count < $1.count })! : first.id)
            let note = entries.compactMap(\.note).first
            let electron = entries.contains { exists($0.book.path + "/Code Cache") && exists($0.book.path + "/Cookies") }
            var summary = first.alias != nil ? "\(first.alias!) 留下的东西，对应的应用已经不在了"
                : first.isBundleID ? "按标识找不到已安装的应用，多半是卸载后留下的" : "认不出是哪个应用或工具的"
            if electron { summary += "；看结构是某个 Electron 应用的数据" }
            let id = shelf("orphan:" + k, .orphans, title, summary)
            update(id) { $0.reason = note }
            entries.forEach { add($0.book, to: id) }
        }
    }

    // MARK: Measuring

    /// Dozens of leftovers under 100 KB are noise one by one; they share one shelf.
    private func foldTinyOrphans() {
        let tiny = order.filter { shelves[$0]?.category == .orphans && (shelves[$0]?.size ?? 0) < 100 * 1024 }
        guard tiny.count > 1 else { return }
        let list = tiny.compactMap { shelves.removeValue(forKey: $0) }
        order.removeAll { tiny.contains($0) }
        var s = Shelf(id: "orphan:tiny", category: .orphans, title: "零碎的小残留（\(list.count) 组）",
                      summary: "都不到 100 KB 的卸载残留：\(list.map(\.title).prefix(12).joined(separator: "、"))\(list.count > 12 ? " 等" : "")")
        s.books = list.flatMap { shelf in shelf.books.map { var b = $0; b.note = [shelf.title, b.note].compactMap { $0 }.joined(separator: "：") ; return b } }
        s.size = list.map(\.size).reduce(0, +)
        s.firstSeen = list.compactMap(\.firstSeen).min()
        s.era = list.compactMap(\.era).min()
        s.lastActive = list.compactMap(\.lastActive).max()
        s.usedSinceArrival = list.contains { $0.usedSinceArrival == true }
        shelves[s.id] = s
        order.append(s.id)
    }

    /// Paths on the sealed system volume or managed by the OS: sizes are meaningless to the user.
    private let unmeasured: Set<String> = ["/System", "/bin", "/sbin", "/usr", "/private/etc", "/System/Applications", "/private/var"]

    private func measure() {
        var refs = [(shelf: String, index: Int, book: Book)]()
        for (id, s) in shelves {
            for (i, b) in s.books.enumerated() { refs.append((id, i, b)) }
        }
        let lock = NSLock()
        var results = [(Int64?, Date?, Date?)](repeating: (nil, nil, nil), count: refs.count)
        DispatchQueue.concurrentPerform(iterations: refs.count) { n in
            let b = refs[n].book
            guard !unmeasured.contains(b.path) else { return }
            let size = b.size ?? measuredSize(b.path)
            let modified = b.kind == .launch ? modificationDate(b.path) : newestModification(b.path, maxDepth: 1, limit: 2000)
            var created = b.created
            if let c = created, Eras.isMigrationDay(c, eras: eras), let inner = oldestCreation(b.path) { created = min(c, inner) }
            lock.lock()
            results[n] = (size, modified, created)
            lock.unlock()
        }
        for (n, ref) in refs.enumerated() {
            shelves[ref.shelf]!.books[ref.index].size = results[n].0
            shelves[ref.shelf]!.books[ref.index].modified = results[n].1
            shelves[ref.shelf]!.books[ref.index].created = results[n].2
        }
    }

    /// Oldest creation date among a folder's direct children: Migration Assistant recreates folders but keeps file dates.
    private func oldestCreation(_ path: String, limit: Int = 500) -> Date? {
        guard isDirectory(path),
              let urls = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.creationDateKey]) else { return nil }
        return urls.prefix(limit).compactMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }
            .filter { $0 > Eras.earliestPlausible }.min()
    }

    private func measuredSize(_ path: String) -> Int64? {
        guard let attrs = try? fm.attributesOfItem(atPath: path) else { return nil }
        if (attrs[.type] as? FileAttributeType) != .typeDirectory {
            return (attrs[.size] as? NSNumber)?.int64Value
        }
        let r = run("/usr/bin/du", ["-sk", path], timeout: 600)
        let field = r.out.split(separator: "\t").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return Int64(field).map { $0 * 1024 }
    }

    private func finalize() {
        let arrival = eras.first(where: \.isCurrent)?.start
        let current = eras.first(where: \.isCurrent)?.index
        let factory = Eras.systemInstallDate()
        for id in order {
            update(id) { s in
                let paths = Set(s.books.map(\.path))
                for i in s.books.indices {
                    var parent = (s.books[i].path as NSString).deletingLastPathComponent
                    while parent.count > 1 {
                        if paths.contains(parent) { s.books[i].nested = true; break }
                        parent = (parent as NSString).deletingLastPathComponent
                    }
                    s.books[i].era = Eras.era(of: s.books[i].created, in: eras)
                    // Apple's own apps are put on the Mac at the factory, between OS install and the user's first login.
                    if s.id.hasPrefix("app:com.apple."), s.books[i].kind == .program, let factory, let arrival,
                       let c = s.books[i].created, c >= factory.addingTimeInterval(-86_400), c < arrival {
                        s.books[i].era = current
                    }
                }
                s.books.sort { ($0.size ?? 0) > ($1.size ?? 0) }
                s.size = s.books.filter { !$0.nested }.compactMap(\.size).reduce(0, +)
                // App bundles are replaced by updates and packages keep their build dates; data folders tell the real story.
                let allDated = s.books.filter { $0.era != nil && $0.created != nil }
                let dataDated = allDated.filter { ![.program, .toolchain].contains($0.kind) }
                let dated = dataDated.isEmpty ? allDated : dataDated
                if let oldest = dated.min(by: { $0.created! < $1.created! }) {
                    s.firstSeen = oldest.created
                    s.era = dated.compactMap(\.era).min()
                }
                s.lastActive = ([s.lastUsed] + s.books.map(\.activity)).compactMap { $0 }.max()
                // Migration itself writes to everything on arrival day; that doesn't count as use.
                if let arrival, s.category != .system {
                    s.usedSinceArrival = s.lastActive.map { $0 >= arrival.addingTimeInterval(86_400) }
                }
            }
        }
    }
}

let appCategoryNames: [String: String] = [
    "public.app-category.business": "商务", "public.app-category.developer-tools": "开发工具",
    "public.app-category.education": "教育", "public.app-category.entertainment": "娱乐",
    "public.app-category.finance": "财务", "public.app-category.games": "游戏",
    "public.app-category.graphics-design": "图形设计", "public.app-category.healthcare-fitness": "健康健身",
    "public.app-category.lifestyle": "生活", "public.app-category.medical": "医疗",
    "public.app-category.music": "音乐", "public.app-category.news": "新闻",
    "public.app-category.photography": "摄影", "public.app-category.productivity": "效率工具",
    "public.app-category.reference": "参考资料", "public.app-category.social-networking": "社交",
    "public.app-category.sports": "体育", "public.app-category.travel": "旅行",
    "public.app-category.utilities": "实用工具", "public.app-category.video": "视频",
    "public.app-category.weather": "天气",
]
