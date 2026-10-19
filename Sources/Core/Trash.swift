import Foundation

/// One item moved to the Trash, kept so it can be put back.
struct TrashRecord: Codable {
    var path: String
    var trashedTo: String
    var date: Date
    var size: Int64?
    /// Title of the shelf it came from.
    var shelf: String
    var book: Book?
    /// The shelf without its books, to put the item back into the catalog.
    var owner: Shelf?
}

enum Trash {
    static var logPath: String { CatalogStore.directory + "/trash-log.json" }

    /// Folders that hold other things; throwing one away would take far more than the user picked.
    private static var containers: Set<String> {
        let h = CatalogStore.home
        let lib = h + "/Library"
        return [h, lib, h + "/Applications", h + "/Desktop", h + "/Documents", h + "/Downloads", h + "/Movies",
                h + "/Music", h + "/Pictures", h + "/Public", h + "/go", h + "/bin", ColdStorage.root,
                lib + "/Application Support", lib + "/Caches", lib + "/Preferences", lib + "/Containers",
                lib + "/Group Containers", lib + "/Logs", lib + "/LaunchAgents",
                "/Applications", "/Library", "/usr/local", "/opt/homebrew", "/Users/Shared"]
    }

    /// Synced or security-critical data that must never go through here.
    private static var untouchable: [String] {
        let lib = CatalogStore.home + "/Library"
        return [lib + "/Mobile Documents", lib + "/CloudStorage", lib + "/Keychains", lib + "/Mail",
                lib + "/Messages", CatalogStore.directory, Bundle.main.bundlePath]
    }

    /// Why this book can't be moved away (to the Trash or cold storage), or nil if it can.
    static func refusal(_ book: Book, in shelf: Shelf) -> String? {
        if shelf.category == .system { return "macOS 自带的东西不动" }
        let p = book.path
        if containers.contains(p) { return "这是存放很多东西的文件夹，请处理里面具体的项" }
        if untouchable.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { return "iCloud、钥匙串、邮件等数据不在这里处理" }
        if (try? fm.attributesOfItem(atPath: p)) == nil { return "已经不在了" }
        let parent = (p as NSString).deletingLastPathComponent
        if book.protected || !fm.isWritableFile(atPath: parent) { return "需要管理员权限，请在访达里处理" }
        return nil
    }

    /// Drops books that sit inside another book of the same batch; moving the outer one takes them along.
    static func outermost(_ books: [Book]) -> [Book] {
        let paths = books.map(\.path)
        return books.filter { b in !paths.contains { $0 != b.path && b.path.hasPrefix($0 + "/") } }
    }

    static func move(_ books: [Book], shelf: Shelf?) -> (moved: [TrashRecord], failed: [(path: String, reason: String)]) {
        var moved = [TrashRecord](), failed = [(path: String, reason: String)]()
        var owner = shelf
        owner?.books = []
        for b in outermost(books) {
            do {
                var result: NSURL?
                try fm.trashItem(at: URL(fileURLWithPath: b.path), resultingItemURL: &result)
                moved.append(TrashRecord(path: b.path, trashedTo: result?.path ?? "", date: Date(), size: b.size,
                                         shelf: shelf?.title ?? "冷藏区", book: b, owner: owner))
            } catch {
                failed.append((b.path, describe(error)))
            }
        }
        writeLog(readLog() + moved)
        return (moved, failed)
    }

    /// What MacTidy put in the Trash that is still there, newest first.
    static func inTrash() -> [TrashRecord] {
        readLog().filter { !$0.trashedTo.isEmpty && (try? fm.attributesOfItem(atPath: $0.trashedTo)) != nil }
            .sorted { $0.date > $1.date }
    }

    /// Puts items back where they were; returns the ones that couldn't be restored.
    static func restore(_ records: [TrashRecord]) -> [(path: String, reason: String)] {
        var failed = [(path: String, reason: String)]()
        var done = Set<String>()
        for r in records {
            if (try? fm.attributesOfItem(atPath: r.path)) != nil { failed.append((r.path, "原位置已有同名的东西")); continue }
            do {
                try fm.createDirectory(atPath: (r.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try fm.moveItem(atPath: r.trashedTo, toPath: r.path)
                done.insert(r.trashedTo)
            } catch {
                failed.append((r.path, fm.fileExists(atPath: r.trashedTo) ? describe(error) : "废纸篓里已经找不到了"))
            }
        }
        writeLog(readLog().filter { !done.contains($0.trashedTo) })
        return failed
    }

    static func describe(_ error: Error) -> String {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain, [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(e.code) {
            return "没有权限，请在访达里处理"
        }
        return e.localizedDescription
    }

    private static func readLog() -> [TrashRecord] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return fm.contents(atPath: logPath).flatMap { try? dec.decode([TrashRecord].self, from: $0) } ?? []
    }

    /// Entries whose Trash copy is gone (the Trash was emptied) are dropped.
    private static func writeLog(_ records: [TrashRecord]) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let live = records.filter { !$0.trashedTo.isEmpty && (try? fm.attributesOfItem(atPath: $0.trashedTo)) != nil }
        try? fm.createDirectory(atPath: CatalogStore.directory, withIntermediateDirectories: true)
        try? enc.encode(live).write(to: URL(fileURLWithPath: logPath), options: .atomic)
    }
}

extension Catalog {
    /// The catalog without the given paths (and anything inside them); shelves left empty disappear.
    func removing(_ paths: [String]) -> Catalog {
        var c = self
        c.shelves = shelves.compactMap { shelf in
            var s = shelf
            s.books.removeAll { b in paths.contains { b.path == $0 || b.path.hasPrefix($0 + "/") } }
            guard s.books.count != shelf.books.count else { return s }
            guard !s.books.isEmpty else { return nil }
            s.size = s.books.filter { !$0.nested }.compactMap(\.size).reduce(0, +)
            return s
        }
        return c
    }
}
