import Foundation

/// One thing in cold storage: what it was, and where it sits inside its batch folder.
struct ColdItem: Codable {
    var book: Book
    var stored: String
}

/// Everything frozen together in one go, usually one shelf or part of it.
struct ColdBatch: Codable, Identifiable {
    var id: String
    var date: Date
    /// The shelf the items came from, without its books; used to put them back into the catalog.
    var shelf: Shelf
    var items: [ColdItem]

    var size: Int64 { items.filter { !$0.book.nested }.compactMap(\.book.size).reduce(0, +) }
    var days: Int { Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0 }
    var isStale: Bool { days >= ColdStorage.staleDays }
}

/// A folder on this Mac where uncertain things wait, still restorable, before being deleted for good.
enum ColdStorage {
    static let folderName = "MacTidy Cold Storage"
    static let manifestName = "manifest.json"
    /// After this long without being missed, frozen things are suggested for deletion.
    static let staleDays = 180
    static var root: String { CatalogStore.home + "/" + folderName }

    static func batches() -> [ColdBatch] {
        children(root).compactMap { name -> ColdBatch? in
            guard let data = fm.contents(atPath: root + "/" + name + "/" + manifestName) else { return nil }
            return try? decoder.decode(ColdBatch.self, from: data)
        }
        .sorted { $0.date > $1.date }
    }

    static func directory(of batch: ColdBatch) -> String { root + "/" + batch.id }

    /// Moves all books or none: an app frozen halfway would be broken in both places.
    static func freeze(_ books: [Book], shelf: Shelf) -> (batch: ColdBatch?, failed: [(path: String, reason: String)]) {
        let books = Trash.outermost(books)
        try? fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        writeReadme()
        let id = uniqueID(for: shelf.title)
        let dir = root + "/" + id
        var moved = [(from: String, to: String)]()
        var items = [ColdItem]()
        for b in books {
            let stored = storedPath(for: b.path)
            let dest = dir + "/" + stored
            do {
                try fm.createDirectory(atPath: (dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try fm.moveItem(atPath: b.path, toPath: dest)
                moved.append((b.path, dest))
                items.append(ColdItem(book: b, stored: stored))
            } catch {
                let unrolled = moved.reversed().filter { (try? fm.moveItem(atPath: $0.to, toPath: $0.from)) == nil }
                if unrolled.isEmpty { try? fm.removeItem(atPath: dir) }
                return (nil, [(b.path, Trash.describe(error))] + unrolled.map { ($0.from, L("Couldn’t move it back; it is now in cold storage at \($0.to)")) })
            }
        }
        var skeleton = shelf
        skeleton.books = []
        let batch = ColdBatch(id: id, date: Date(), shelf: skeleton, items: items)
        do {
            try save(batch)
        } catch {
            return (batch, [(dir, L("Couldn’t write the manifest: \(error.localizedDescription)"))])
        }
        return (batch, [])
    }

    /// Puts items back; whatever couldn't go back stays frozen and in the manifest.
    static func thaw(_ batch: ColdBatch, only paths: Set<String>? = nil) -> (restored: [Book], failed: [(path: String, reason: String)]) {
        let dir = directory(of: batch)
        var restored = [Book](), failed = [(path: String, reason: String)](), remaining = [ColdItem]()
        for item in batch.items {
            guard paths?.contains(item.book.path) ?? true else { remaining.append(item); continue }
            let src = dir + "/" + item.stored
            do {
                if (try? fm.attributesOfItem(atPath: item.book.path)) != nil { throw Conflict() }
                try fm.createDirectory(atPath: (item.book.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try fm.moveItem(atPath: src, toPath: item.book.path)
                restored.append(item.book)
            } catch is Conflict {
                failed.append((item.book.path, L("Something with the same name is already at the original location")))
                remaining.append(item)
            } catch {
                failed.append((item.book.path, fm.fileExists(atPath: src) ? Trash.describe(error) : L("No longer in cold storage")))
                if fm.fileExists(atPath: src) { remaining.append(item) }
            }
        }
        if remaining.isEmpty {
            if !containsFiles(dir, except: manifestName) { try? fm.removeItem(atPath: dir) }
        } else {
            var b = batch
            b.items = remaining
            try? save(b)
        }
        return (restored, failed)
    }

    /// Deletion, still recoverable: the whole batch folder goes to the Trash.
    static func discard(_ batch: ColdBatch) -> (record: TrashRecord?, failure: String?) {
        let dir = directory(of: batch)
        let book = Book(path: dir, kind: .folder, size: batch.size, created: batch.date,
                        note: L("“\(batch.shelf.title)” from cold storage, \(batch.items.count) items"))
        let result = Trash.move([book], shelf: nil)
        return (result.moved.first, result.failed.first?.reason)
    }

    private struct Conflict: Error {}

    /// Keeps the original layout readable: `Home/Library/Caches/x`, `Root/Applications/X.app`.
    private static func storedPath(for path: String) -> String {
        let home = CatalogStore.home
        return path.hasPrefix(home + "/") ? "Home/" + path.dropFirst(home.count + 1) : "Root" + path
    }

    private static func uniqueID(for title: String) -> String {
        let day = Date().formatted(.iso8601.year().month().day())
        let clean = title.replacingOccurrences(of: #"[/:]"#, with: "-", options: .regularExpression).prefix(60)
        var id = "\(day) \(clean)", n = 2
        while fm.fileExists(atPath: root + "/" + id) { id = "\(day) \(clean) \(n)"; n += 1 }
        return id
    }

    private static func containsFiles(_ dir: String, except name: String) -> Bool {
        guard let e = fm.enumerator(atPath: dir) else { return false }
        while let rel = e.nextObject() as? String {
            var isDir: ObjCBool = false
            if rel != name, fm.fileExists(atPath: dir + "/" + rel, isDirectory: &isDir), !isDir.boolValue { return true }
        }
        return false
    }

    private static func save(_ batch: ColdBatch) throws {
        try encoder.encode(batch).write(to: URL(fileURLWithPath: directory(of: batch) + "/" + manifestName), options: .atomic)
    }

    private static func writeReadme() {
        let path = root + "/README.txt"
        guard !fm.fileExists(atPath: path) else { return }
        let text = L("""
        This is MacTidy’s cold storage.
        Things you weren’t sure about wait here; each folder’s \(manifestName) records where they came from.
        To put something back, use Put Back in MacTidy’s Cold Storage. If you move things here by hand, MacTidy can’t put them back.
        Anything you haven’t missed for half a year can usually be deleted.
        """)
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Things the user decided to keep: no more "unused" reminders for them.
struct Decisions: Codable {
    var keptShelves: Set<String> = []
    var keptPaths: Set<String> = []

    static var path: String { CatalogStore.directory + "/decisions.json" }

    static func load() -> Decisions {
        fm.contents(atPath: path).flatMap { try? JSONDecoder().decode(Decisions.self, from: $0) } ?? Decisions()
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? fm.createDirectory(atPath: CatalogStore.directory, withIntermediateDirectories: true)
        try? enc.encode(self).write(to: URL(fileURLWithPath: Decisions.path), options: .atomic)
    }
}

extension Catalog {
    /// Puts books back onto their shelf, recreating it if it had disappeared.
    func inserting(_ books: [Book], into shelf: Shelf) -> Catalog {
        guard !books.isEmpty else { return self }
        var c = self
        if let i = c.shelves.firstIndex(where: { $0.id == shelf.id }) {
            let existing = Set(c.shelves[i].books.map(\.path))
            c.shelves[i].books += books.filter { !existing.contains($0.path) }
            c.shelves[i].size = c.shelves[i].books.filter { !$0.nested }.compactMap(\.size).reduce(0, +)
        } else {
            var s = shelf
            s.books = books
            s.size = books.filter { !$0.nested }.compactMap(\.size).reduce(0, +)
            c.shelves.append(s)
        }
        return c
    }
}
