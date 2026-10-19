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
}
