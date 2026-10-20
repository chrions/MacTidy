import AppKit
import Observation
import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case category(Category)
    case coldRoom
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
    private(set) var decisions = Decisions.load()
    private(set) var coldBatches: [ColdBatch] = []
    private(set) var trashed: [TrashRecord] = []

    init() {
        if let c = CatalogStore.load() { set(c) }
        refreshShelves()
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

    /// Updates the catalog after files moved, and remembers it for the next launch.
    private func commit(_ catalog: Catalog) {
        set(catalog)
        try? CatalogStore.save(catalog)
    }

    func refreshShelves() {
        coldBatches = ColdStorage.batches()
        trashed = Trash.inTrash()
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
            refreshShelves()
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

    func isKept(_ shelf: Shelf) -> Bool { decisions.keptShelves.contains(shelf.id) }
    func isKept(_ book: Book, in shelf: Shelf) -> Bool { isKept(shelf) || decisions.keptPaths.contains(book.path) }

    /// Unused since arriving, and the user hasn't said to keep it.
    func flaggedUnused(_ book: Book, in shelf: Shelf) -> Bool { used(book) == false && !isKept(book, in: shelf) }

    func flaggedUnused(_ unit: CatalogReport.Unit) -> Bool {
        guard unit.used == false, let s = shelf(unit.shelfID) else { return false }
        if isKept(s) { return false }
        return unit.bookPath.map { !decisions.keptPaths.contains($0) } ?? true
    }

    /// For collections: how many of the (non-nested) books haven't been used since arriving.
    func unusedCount(_ shelf: Shelf) -> (unused: Int, total: Int) {
        let books = shelf.books.filter { !$0.nested }
        return (books.filter { flaggedUnused($0, in: shelf) }.count, books.count)
    }

    func isUnused(_ shelf: Shelf) -> Bool {
        if isKept(shelf) { return false }
        return CatalogReport.isCollection(shelf) ? unusedCount(shelf).unused > 0 : shelf.usedSinceArrival == false
    }

    func matchesEra(_ shelf: Shelf) -> Bool {
        guard let eraFilter else { return true }
        return CatalogReport.isCollection(shelf) ? shelf.books.contains { $0.era == eraFilter } : shelf.era == eraFilter
    }

    /// Books shown for a shelf under the current filters.
    func visibleBooks(_ shelf: Shelf) -> [Book] {
        guard CatalogReport.isCollection(shelf) else { return shelf.books }
        return shelf.books.filter { b in
            (eraFilter == nil || b.era == eraFilter) && (!onlyUnused || flaggedUnused(b, in: shelf))
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

    var coldSize: Int64 { coldBatches.map(\.size).reduce(0, +) }

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

    // MARK: Keep

    func toggleKeep(_ shelf: Shelf) {
        if decisions.keptShelves.remove(shelf.id) == nil { decisions.keptShelves.insert(shelf.id) }
        decisions.save()
    }

    func toggleKeep(_ book: Book) {
        if decisions.keptPaths.remove(book.path) == nil { decisions.keptPaths.insert(book.path) }
        decisions.save()
    }

    func unkeep(shelfID: String? = nil, path: String? = nil) {
        if let shelfID { decisions.keptShelves.remove(shelfID) }
        if let path { decisions.keptPaths.remove(path) }
        decisions.save()
    }

    // MARK: Moving things away

    enum Action {
        case trash, freeze
        /// Deleting something already in cold storage.
        case discard(ColdBatch)
    }

    struct PendingAction: Identifiable {
        let id = UUID()
        let action: Action
        let shelf: Shelf
        let books: [Book]
        /// Set when the move must not happen yet, e.g. the app is still running.
        let blocked: String?
        let warnings: [String]
        var size: Int64 { books.filter { !$0.nested }.compactMap(\.size).reduce(0, +) }
    }

    struct Outcome {
        enum Undo { case trash([TrashRecord]), freeze(ColdBatch) }
        let message: String
        let failed: [(path: String, reason: String)]
        let undo: Undo?
    }

    var pending: PendingAction?
    var outcome: Outcome?

    func refusal(_ book: Book, in shelf: Shelf) -> String? { Trash.refusal(book, in: shelf) }

    /// Books on the shelf that could be moved, optionally only the ones flagged unused.
    func movable(_ shelf: Shelf, onlyUnused: Bool) -> [Book] {
        Trash.outermost(shelf.books.filter { b in
            refusal(b, in: shelf) == nil && (!onlyUnused || (!b.nested && flaggedUnused(b, in: shelf)))
        })
    }

    func request(_ action: Action, _ books: [Book], in shelf: Shelf) {
        let books = Trash.outermost(books)
        guard !books.isEmpty else { return }
        var warnings = [String]()
        let isApp = books.contains { $0.kind == .program && $0.path.hasSuffix(".app") }
        switch action {
        case .trash:
            if isApp { warnings.append("包含应用本体，相当于卸载这个应用。") }
        case .freeze:
            if isApp { warnings.append("应用会连同数据一起挪走，冷藏期间打不开；放回后照常使用。") }
            if books.contains(where: { $0.kind == .launch || $0.kind == .helper }) {
                warnings.append("包含开机服务或帮助程序，冷藏后相关功能会停用。")
            }
        case .discard(let batch):
            if !batch.isStale { warnings.append("才冷藏了 \(batch.days) 天。") }
        }
        let usedCount = books.filter { used($0) == true }.count
        if usedCount > 0 { warnings.append("其中 \(usedCount) 项搬到这台 Mac 后还用过。") }
        if books.contains(where: { $0.kind == .secret }) {
            warnings.append("包含密钥或凭据，挪走后可能登录不了对应的服务器或服务。")
        }
        if books.contains(where: { $0.kind == .config || $0.kind == .toolchain || $0.kind == .command }) {
            warnings.append("包含配置或命令，相关工具可能会报错。")
        }
        pending = PendingAction(action: action, shelf: shelf, books: books, blocked: runningBlock(books), warnings: warnings)
    }

    private func runningBlock(_ books: [Book]) -> String? {
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard let path = app.bundleURL?.path,
                  books.contains(where: { path == $0.path || path.hasPrefix($0.path + "/") }) else { return nil }
            return app.localizedName ?? (path as NSString).lastPathComponent
        }
        return running.isEmpty ? nil : "\(running.joined(separator: "、")) 正在运行，请先退出。"
    }

    func confirm() {
        guard let p = pending, p.blocked == nil, let current = catalog else { return }
        pending = nil
        switch p.action {
        case .trash:
            let r = Trash.move(p.books, shelf: p.shelf)
            if !r.moved.isEmpty { commit(current.removing(r.moved.map(\.path))) }
            let size = r.moved.compactMap(\.size).reduce(0, +)
            outcome = Outcome(message: r.moved.isEmpty ? "没能移到废纸篓" : "已移到废纸篓 \(r.moved.count) 项 · \(Fmt.size(size))",
                              failed: r.failed, undo: r.moved.isEmpty ? nil : .trash(r.moved))
        case .freeze:
            let r = ColdStorage.freeze(p.books, shelf: p.shelf)
            if let batch = r.batch {
                commit(current.removing(batch.items.map(\.book.path)))
                outcome = Outcome(message: "已冷藏 \(batch.items.count) 项 · \(Fmt.size(batch.size))", failed: r.failed, undo: .freeze(batch))
            } else {
                outcome = Outcome(message: "没能冷藏，所有东西都留在原处", failed: r.failed, undo: nil)
            }
        case .discard(let batch):
            let r = ColdStorage.discard(batch)
            outcome = Outcome(message: r.record == nil ? "没能移到废纸篓" : "已把冷藏的「\(batch.shelf.title)」移到废纸篓",
                              failed: r.failure.map { [(ColdStorage.directory(of: batch), $0)] } ?? [],
                              undo: r.record.map { .trash([$0]) })
        }
        refreshShelves()
    }

    func undo() {
        guard let undo = outcome?.undo else { return }
        switch undo {
        case .trash(let records): restore(records)
        case .freeze(let batch): thaw(batch)
        }
    }

    func thaw(_ batch: ColdBatch) {
        let r = ColdStorage.thaw(batch)
        if let current = catalog, !r.restored.isEmpty { commit(current.inserting(r.restored, into: batch.shelf)) }
        let size = r.restored.filter { !$0.nested }.compactMap(\.size).reduce(0, +)
        outcome = Outcome(message: r.restored.isEmpty ? "没能放回" : "已放回原处 \(r.restored.count) 项 · \(Fmt.size(size))",
                          failed: r.failed, undo: nil)
        refreshShelves()
    }

    func restore(_ records: [TrashRecord]) {
        let failed = Trash.restore(records)
        let back = records.filter { r in !failed.contains { $0.path == r.path } }
        if var c = catalog {
            for r in back {
                if let book = r.book, let owner = r.owner { c = c.inserting([book], into: owner) }
            }
            commit(c)
        }
        outcome = Outcome(message: back.isEmpty ? "没能放回" : "已从废纸篓放回 \(back.count) 项", failed: failed, undo: nil)
        refreshShelves()
    }

    func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: CatalogStore.home + "/.Trash"))
    }

    // MARK: AI recognition

    var aiConfig = AIConfig.load()
    private(set) var aiNotes = AINotes.load()
    private(set) var aiProgress: String?
    var aiError: String?
    private var aiTask: Task<Void, Never>?

    var aiReady: Bool { aiConfig.isComplete }

    /// Shelves (and items) whose names alone could leak secrets are never sent.
    private static let privateShelves: Set<String> = ["mine:secret", "term:secrets"]

    func aiKey(_ shelf: Shelf) -> String { "shelf:" + shelf.id }
    func aiKey(_ book: Book) -> String { "path:" + book.path }

    func aiNote(_ shelf: Shelf) -> AINote? { aiNotes[aiKey(shelf)] }
    func aiNote(_ book: Book) -> AINote? { aiNotes[aiKey(book)] }

    /// Items left out because their names look like personal documents or credentials.
    func aiWithheld(_ shelf: Shelf) -> Int {
        guard CatalogReport.isCollection(shelf), !Self.privateShelves.contains(shelf.id) else { return 0 }
        return shelf.books.filter { !$0.nested && $0.kind != .secret && AIPrivacy.isSensitive(($0.path as NSString).lastPathComponent) }.count
    }

    /// Collections are recognised item by item; other shelves as a whole. Everything is passed through `AIPrivacy`.
    func aiTargets(_ shelf: Shelf) -> [(key: String, subject: AISubject)] {
        let blocked = aiConfig.blockedWords ?? []
        return rawTargets(shelf).map { t in
            var s = t.subject
            s.title = AIPrivacy.clean(s.title, blocked: blocked)
            s.summary = AIPrivacy.clean(s.summary, blocked: blocked)
            s.paths = s.paths.map { AIPrivacy.clean($0, blocked: blocked) }
            return (t.key, s)
        }
    }

    private func rawTargets(_ shelf: Shelf) -> [(key: String, subject: AISubject)] {
        guard shelf.category != .system, !Self.privateShelves.contains(shelf.id) else { return [] }
        if CatalogReport.isCollection(shelf) {
            return shelf.books.filter {
                !$0.nested && $0.kind != .secret && !AIPrivacy.isSensitive(($0.path as NSString).lastPathComponent)
            }.map { b in
                (aiKey(b), AISubject(id: "", title: (b.path as NSString).lastPathComponent, category: shelf.category.rawValue,
                                     summary: [shelf.title, b.note].compactMap { $0 }.joined(separator: "；"),
                                     paths: [Fmt.path(b.path)], kinds: [b.kind.rawValue], size: Fmt.size(b.size),
                                     cameFrom: eraName(b.era), lastActive: Fmt.day(b.activity ?? b.modified),
                                     usedSinceArrival: usedLabel(used(b))))
            }
        }
        let books = shelf.books.filter { $0.kind != .secret }
        guard !books.isEmpty else { return [] }
        return [(aiKey(shelf), AISubject(id: "", title: shelf.title, category: shelf.category.rawValue, summary: shelf.summary,
                                         paths: books.prefix(10).map { Fmt.path($0.path) },
                                         kinds: Array(Set(books.map(\.kind.rawValue))).sorted(), size: Fmt.size(shelf.size),
                                         cameFrom: eraName(shelf.era), lastActive: Fmt.day(shelf.lastActive),
                                         usedSinceArrival: usedLabel(shelf.usedSinceArrival)))]
    }

    private func usedLabel(_ used: Bool?) -> String {
        switch used { case true?: return "用过"; case false?: return "没用过"; default: return "无记录" }
    }

    func aiPendingCount(_ shelves: [Shelf]) -> Int {
        shelves.flatMap(aiTargets).filter { aiNotes[$0.key] == nil }.count
    }

    /// Asks the AI about everything on these shelves it hasn't seen yet (or again, with `force`).
    func recognise(_ shelves: [Shelf], force: Bool = false) {
        var targets = shelves.flatMap(aiTargets)
        if !force { targets = targets.filter { aiNotes[$0.key] == nil } }
        run(targets)
    }

    /// A whole category at once: confirmed first, since it can be many requests.
    struct PendingRecognition: Identifiable {
        let id = UUID()
        let shelves: [Shelf]
        let count: Int
        let withheld: Int
    }

    var pendingRecognition: PendingRecognition?

    func requestRecognition(_ shelves: [Shelf]) {
        guard aiReady else { aiError = "先在设置里填好 AI 的接口地址和模型（⌘,）"; return }
        let count = aiPendingCount(shelves)
        guard count > 0 else { return }
        pendingRecognition = PendingRecognition(shelves: shelves, count: count, withheld: shelves.map(aiWithheld).reduce(0, +))
    }

    func confirmRecognition() {
        guard let p = pendingRecognition else { return }
        pendingRecognition = nil
        recognise(p.shelves)
    }

    var aiServiceName: String {
        AIConfig.presets.first { $0.baseURL == aiConfig.baseURL }?.name ?? (URL(string: aiConfig.baseURL)?.host ?? aiConfig.baseURL)
    }

    func recognise(item book: Book, in shelf: Shelf) {
        run(aiTargets(shelf).filter { $0.key == aiKey(book) })
    }

    private func run(_ targets: [(key: String, subject: AISubject)]) {
        guard aiProgress == nil, !targets.isEmpty else { return }
        guard aiReady else { aiError = "先在设置里填好 AI 的接口地址和模型（⌘,）"; return }
        aiError = nil
        let client = AIClient(config: aiConfig, key: AIKey.read(for: aiConfig.baseURL))
        let batches = stride(from: 0, to: targets.count, by: AIClient.batchSize).map {
            Array(targets[$0..<min($0 + AIClient.batchSize, targets.count)])
        }
        aiProgress = "AI 识别中…"
        aiTask = Task {
            for (n, batch) in batches.enumerated() {
                if Task.isCancelled { break }
                aiProgress = batches.count > 1 ? "AI 识别中 \(n + 1)/\(batches.count) 批" : "AI 识别中…"
                var keys = [String: String]()
                let subjects = batch.enumerated().map { i, t -> AISubject in
                    var s = t.subject
                    s.id = String(i + 1)
                    keys[s.id] = t.key
                    return s
                }
                do {
                    let notes = try await client.recognise(subjects)
                    for (id, note) in notes { if let key = keys[id] { aiNotes[key] = note } }
                    AINotes.save(aiNotes)
                } catch is CancellationError {
                    break
                } catch {
                    if (error as? URLError)?.code == .cancelled { break }
                    aiError = error.localizedDescription
                    break
                }
            }
            aiProgress = nil
            aiTask = nil
        }
    }

    func cancelRecognition() {
        aiTask?.cancel()
    }

    func forget(_ key: String) {
        aiNotes[key] = nil
        AINotes.save(aiNotes)
    }

    func openColdRoom() {
        try? FileManager.default.createDirectory(atPath: ColdStorage.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: ColdStorage.root))
    }
}
