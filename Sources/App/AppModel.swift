import AppKit
import Observation
import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case category(Category)
}

extension Category {
    var symbol: String {
        switch self {
        case .system: return "apple.logo"
        case .apps: return "square.stack"
        case .dev: return "hammer"
        case .terminal: return "terminal"
        case .personal: return "folder"
        case .orphans: return "questionmark.folder"
        }
    }
}

extension Shelf: Identifiable {}

@MainActor
@Observable
final class AppModel {
    private(set) var catalog: Catalog?
    private(set) var report: CatalogReport?
    private(set) var scanning = false
    private(set) var progress = ""
    var sidebar: SidebarItem? = .overview
    var selectedShelf: String?
    var eraFilter: Int?
    var onlyUnused = false
    var search = ""
    /// Book to scroll to and highlight after jumping from the overview.
    var focusedBook: String?

    let hasFullDiskAccess = (try? FileManager.default.contentsOfDirectory(atPath: CatalogStore.home + "/Library/Safari")) != nil

    private(set) var units: [CatalogReport.Unit] = []

    init() {
        if let c = CatalogStore.load() { set(c) }
    }

    private func set(_ catalog: Catalog) {
        var catalog = catalog
        catalog.eras = Eras.named(catalog.eras)
        self.catalog = catalog
        let report = CatalogReport(catalog: catalog, home: CatalogStore.home)
        self.report = report
        units = report.units
        if shelf(selectedShelf) == nil { selectedShelf = nil }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        progress = "准备扫描"
        let report: @Sendable (String) -> Void = { [weak self] step in
            Task { @MainActor in self?.progress = step }
        }
        Task {
            let catalog = await Task.detached(priority: .userInitiated) {
                let c = CatalogStore.scan(progress: report)
                try? CatalogStore.save(c)
                return c
            }.value
            set(catalog)
            scanning = false
        }
    }

    // MARK: Derived data

    var eras: [Era] {
        guard let catalog else { return [] }
        let used = Set(units.compactMap(\.era))
        return catalog.eras.filter { $0.start != nil || used.contains($0.index) }
    }

    func eraName(_ index: Int?) -> String { report?.eraName(index) ?? "不详" }

    /// Activity after this moment counts as use on the current Mac (the migration day itself doesn't).
    var usedThreshold: Date? { catalog?.eras.first(where: \.isCurrent)?.start?.addingTimeInterval(86_400) }

    func used(_ book: Book) -> Bool? {
        if book.idle { return false }
        guard let a = book.activity, let t = usedThreshold else { return nil }
        return a >= t
    }

    /// For collections: how many of the (non-nested) books haven't been used since arriving.
    func unusedCount(_ shelf: Shelf) -> (unused: Int, total: Int) {
        let books = shelf.books.filter { !$0.nested }
        return (books.filter { used($0) == false }.count, books.count)
    }

    func isUnused(_ shelf: Shelf) -> Bool {
        CatalogReport.isCollection(shelf) ? shelf.books.contains { !$0.nested && used($0) == false } : shelf.usedSinceArrival == false
    }

    func matchesEra(_ shelf: Shelf) -> Bool {
        guard let eraFilter else { return true }
        return CatalogReport.isCollection(shelf) ? shelf.books.contains { $0.era == eraFilter } : shelf.era == eraFilter
    }

    /// Books shown for a shelf under the current filters.
    func visibleBooks(_ shelf: Shelf) -> [Book] {
        guard CatalogReport.isCollection(shelf) else { return shelf.books }
        return shelf.books.filter { b in
            (eraFilter == nil || b.era == eraFilter) && (!onlyUnused || used(b) == false)
        }
    }

    func shelves(in category: Category?) -> [Shelf] {
        guard let catalog else { return [] }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog.shelves.filter { s in
            (category == nil || s.category == category)
                && matchesEra(s)
                && (!onlyUnused || isUnused(s))
                && (query.isEmpty || s.title.lowercased().contains(query) || s.summary.lowercased().contains(query)
                    || s.books.contains { $0.path.lowercased().contains(query) })
        }
        .sorted { $0.size > $1.size }
    }

    func size(of category: Category) -> Int64 {
        catalog?.shelves.filter { $0.category == category }.map(\.size).reduce(0, +) ?? 0
    }

    func shelf(_ id: String?) -> Shelf? {
        guard let id else { return nil }
        return catalog?.shelves.first { $0.id == id }
    }

    func open(_ unit: CatalogReport.Unit) {
        sidebar = .category(unit.category)
        selectedShelf = unit.shelfID
        focusedBook = unit.bookPath
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: Trash

    struct TrashRequest: Identifiable {
        let id = UUID()
        let shelf: Shelf
        let books: [Book]
        /// Set when the move must not happen yet, e.g. the app is still running.
        let blocked: String?
        let warnings: [String]
        var size: Int64 { books.filter { !$0.nested }.compactMap(\.size).reduce(0, +) }
    }

    struct TrashOutcome {
        let moved: [TrashRecord]
        let failed: [(path: String, reason: String)]
        let before: Catalog
        var undone = false
    }

    var trashRequest: TrashRequest?
    var trashOutcome: TrashOutcome?

    func trashRefusal(_ book: Book, in shelf: Shelf) -> String? { Trash.refusal(book, in: shelf) }

    /// Books on the shelf that could go, optionally only the ones unused since arriving.
    func trashable(_ shelf: Shelf, onlyUnused: Bool) -> [Book] {
        Trash.outermost(shelf.books.filter { b in
            trashRefusal(b, in: shelf) == nil && (!onlyUnused || (!b.nested && used(b) == false))
        })
    }

    func requestTrash(_ books: [Book], in shelf: Shelf) {
        let books = Trash.outermost(books)
        guard !books.isEmpty else { return }
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard let path = app.bundleURL?.path,
                  books.contains(where: { path == $0.path || path.hasPrefix($0.path + "/") }) else { return nil }
            return app.localizedName ?? (path as NSString).lastPathComponent
        }
        var warnings = [String]()
        if books.contains(where: { $0.kind == .program && $0.path.hasSuffix(".app") }) {
            warnings.append("包含应用本体，相当于卸载这个应用。")
        }
        let usedCount = books.filter { used($0) == true }.count
        if usedCount > 0 { warnings.append("其中 \(usedCount) 项搬到这台 Mac 后还用过。") }
        if books.contains(where: { $0.kind == .secret }) {
            warnings.append("包含密钥或凭据，扔掉后可能登录不了对应的服务器或服务。")
        }
        if books.contains(where: { $0.kind == .config || $0.kind == .toolchain || $0.kind == .command }) {
            warnings.append("包含配置或命令，相关工具可能会报错。")
        }
        let blocked = running.isEmpty ? nil : "\(running.joined(separator: "、")) 正在运行，请先退出再扔。"
        trashRequest = TrashRequest(shelf: shelf, books: books, blocked: blocked, warnings: warnings)
    }

    func confirmTrash() {
        guard let request = trashRequest, request.blocked == nil, let before = catalog else { return }
        trashRequest = nil
        let result = Trash.move(request.books, shelf: request.shelf.title)
        trashOutcome = TrashOutcome(moved: result.moved, failed: result.failed, before: before)
        guard !result.moved.isEmpty else { return }
        let updated = before.removing(result.moved.map(\.path))
        set(updated)
        try? CatalogStore.save(updated)
    }

    func undoTrash() {
        guard var outcome = trashOutcome, !outcome.undone else { return }
        let failed = Trash.restore(outcome.moved)
        let restored = outcome.moved.filter { r in !failed.contains { $0.path == r.path } }.map(\.path)
        if let current = catalog, !restored.isEmpty {
            var c = current
            let keep = outcome.before.removing(outcome.moved.map(\.path).filter { !restored.contains($0) })
            c.shelves = keep.shelves
            set(c)
            try? CatalogStore.save(c)
        }
        outcome.undone = true
        trashOutcome = failed.isEmpty ? nil : TrashOutcome(moved: [], failed: failed, before: outcome.before, undone: true)
    }

    func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: CatalogStore.home + "/.Trash"))
    }
}
