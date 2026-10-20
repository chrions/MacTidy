import SwiftUI

/// List of shelves on the left, the selected shelf on the right. `category == nil` searches everything.
struct CategoryBrowser: View {
    @Environment(AppModel.self) private var model
    let category: Category?

    var body: some View {
        let shelves = model.shelves(in: category)
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                header(shelves)
                Divider()
                if shelves.isEmpty {
                    ContentUnavailableView("Nothing matches", systemImage: "line.3.horizontal.decrease",
                                           description: Text("Try clearing the filters"))
                } else {
                    List(shelves) { s in
                        ShelfRow(shelf: s)
                            .padding(.horizontal, 8)
                            .background(model.selectedShelf == s.id ? Color.primary.opacity(0.08) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedShelf = s.id }
                            .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)

            Group {
                if let shelf = model.shelf(model.selectedShelf) {
                    ShelfDetail(shelf: shelf)
                } else {
                    ContentUnavailableView("Select a shelf", systemImage: "books.vertical")
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ shelves: [Shelf]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category?.name ?? L("Search Results")).font(.title2.weight(.semibold))
            Text(category?.blurb ?? L("Name, description or path contains “\(model.search)”")).font(.callout).foregroundStyle(.secondary)
            Text(L("\(shelves.count) shelves · \(Fmt.size(shelves.map(\.size).reduce(0, +)))"))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit().padding(.top, 2)
            if category == .orphans || category == .personal {
                let pending = model.aiPendingCount(shelves)
                if pending > 0 {
                    AIButton(title: L("Ask the AI about this category (\(pending) items)")) { model.requestRecognition(shelves) }
                        .padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShelfRow: View {
    @Environment(AppModel.self) private var model
    let shelf: Shelf

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shelf.title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let tag = unusedTag { Tag(tag) }
            Text(Fmt.size(shelf.size)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var unusedTag: String? {
        if model.isKept(shelf) { return L("Kept") }
        guard CatalogReport.isCollection(shelf) else { return shelf.usedSinceArrival == false ? L("Unused") : nil }
        let (unused, total) = model.unusedCount(shelf)
        if unused == 0 { return nil }
        return unused == total ? L("Unused") : L("\(unused) unused")
    }

    private var subtitle: String {
        if CatalogReport.isCollection(shelf) { return L("\(model.visibleBooks(shelf).count) items · \(shelf.summary)") }
        let summary = model.aiNote(shelf).map { L("AI: \($0.owner ?? $0.what)") } ?? shelf.summary
        return shelf.category == .system ? summary : "\(model.eraName(shelf.era)) · \(summary)"
    }
}

struct ShelfDetail: View {
    @Environment(AppModel.self) private var model
    let shelf: Shelf

    var body: some View {
        let books = model.visibleBooks(shelf)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(shelf.category.name).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(shelf.title).font(.system(size: 26, weight: .semibold)).textSelection(.enabled)
                        Text(shelf.summary).foregroundStyle(.secondary)
                    }

                    ShelfActions(shelf: shelf)

                    AICard(shelf: shelf)

                    HStack(alignment: .top, spacing: 16) {
                        Fact(label: L("Size"), value: Fmt.size(shelf.size))
                        if shelf.category != .system {
                            Fact(label: L("From"), value: model.eraName(shelf.era))
                            Fact(label: L("Last activity"), value: Fmt.day(shelf.lastActive))
                            Fact(label: L("Since arriving"), value: usedText)
                        }
                    }

                    if !shelf.flags.isEmpty || shelf.reason != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            if !shelf.flags.isEmpty {
                                FlowLayout { ForEach(shelf.flags, id: \.self) { Tag($0) } }
                            }
                            if let reason = shelf.reason { Text(reason).font(.callout).foregroundStyle(.secondary) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: L("Locations"), subtitle: books.count == shelf.books.count ? L("\(books.count) places")
                                     : L("\(books.count) of \(shelf.books.count) places match the filters"))
                        VStack(spacing: 0) {
                            ForEach(Array(books.enumerated()), id: \.element.path) { i, b in
                                if i > 0 { Divider() }
                                BookRow(book: b, shelf: shelf, highlighted: model.focusedBook == b.path)
                                    .id(b.path)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { scroll(proxy) }
            .onChange(of: model.focusedBook) { scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let target = model.focusedBook else { return }
        withAnimation { proxy.scrollTo(target, anchor: .center) }
    }

    private var usedText: String {
        if model.isKept(shelf) { return L("Kept") }
        if CatalogReport.isCollection(shelf) {
            let (unused, total) = model.unusedCount(shelf)
            return unused == 0 ? L("All used") : unused == total ? L("None used") : L("\(unused) unused")
        }
        switch shelf.usedSinceArrival {
        case true?: return L("Used")
        case false?: return L("Unused")
        default: return L("No record")
        }
    }
}

/// Starts recognition, or leads to Settings when no endpoint is configured yet.
struct AIButton: View {
    @Environment(AppModel.self) private var model
    let title: String
    let action: () -> Void

    var body: some View {
        if model.aiReady {
            Button(action: action) { Label(title, systemImage: "sparkles") }
                .buttonStyle(.bordered)
                .disabled(model.aiProgress != nil)
        } else {
            SettingsLink { Label("Set Up AI Recognition…", systemImage: "sparkles") }
                .buttonStyle(.bordered)
        }
    }
}

/// What the AI said about this shelf, or how far it got with the items of a collection.
private struct AICard: View {
    @Environment(AppModel.self) private var model
    let shelf: Shelf

    var body: some View {
        let targets = model.aiTargets(shelf)
        if !targets.isEmpty {
            if CatalogReport.isCollection(shelf) {
                let pending = targets.filter { model.aiNotes[$0.key] == nil }.count
                HStack(spacing: 10) {
                    if pending > 0 {
                        AIButton(title: L("Ask the AI about these \(pending) items")) { model.requestRecognition([shelf]) }
                    }
                    if pending < targets.count {
                        Text(L("\(targets.count - pending) recognised; see each item below")).font(.caption).foregroundStyle(.secondary)
                        Button("Recognise All Again") { model.recognise([shelf], force: true) }
                            .buttonStyle(.borderless).font(.caption).disabled(model.aiProgress != nil)
                    }
                    let withheld = model.aiWithheld(shelf)
                    if withheld > 0 {
                        Text(L("\(withheld) look like ID documents, contracts or keys and aren't sent to the AI")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if let note = model.aiNote(shelf) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.caption)
                        Text("AI Recognition").font(.caption.weight(.medium))
                        if let advice = note.suggestion { Tag(advice.label, filled: advice == .delete) }
                        Spacer()
                        Button("Recognise Again") { model.recognise([shelf], force: true) }
                            .buttonStyle(.borderless).font(.caption).disabled(model.aiProgress != nil)
                    }
                    .foregroundStyle(.secondary)
                    if let owner = note.owner { Text(owner).font(.headline) }
                    Text(note.what).textSelection(.enabled)
                    if let reason = note.reason { Text(reason).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                    Text(L("\(note.model) · \(Fmt.day(note.date)) · Inferred from names and paths only; for reference"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.04)))
            } else {
                AIButton(title: L("Ask the AI What This Is")) { model.recognise([shelf]) }
            }
        }
    }
}

/// Keep, freeze or throw away. Collections act on what hasn't been used; other shelves go as a whole.
private struct ShelfActions: View {
    @Environment(AppModel.self) private var model
    let shelf: Shelf

    var body: some View {
        if shelf.category != .system {
            let collection = CatalogReport.isCollection(shelf)
            let kept = model.isKept(shelf)
            let books = kept ? [] : model.movable(shelf, onlyUnused: collection)
            let total = Trash.outermost(collection ? shelf.books.filter { !$0.nested && model.flaggedUnused($0, in: shelf) } : shelf.books).count
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button { model.toggleKeep(shelf) } label: {
                        Label(kept ? L("Unkeep") : L("Keep"), systemImage: kept ? "pin.slash" : "pin")
                    }
                    .help(kept ? L("Remind me again about unused things on this shelf") : L("Stop reminding me that this shelf is unused"))
                    if !books.isEmpty {
                        Button { model.request(.freeze, books, in: shelf) } label: {
                            Label(collection ? L("Freeze \(books.count) Unused…") : L("Freeze All…"), systemImage: "snowflake")
                        }
                        .help("Move to cold storage; can be put back anytime")
                        Button(role: .destructive) { model.request(.trash, books, in: shelf) } label: {
                            Label(collection ? L("Move \(books.count) Unused to Trash…") : L("Move All to Trash…"), systemImage: "trash")
                        }
                    }
                }
                .buttonStyle(.bordered)
                if !books.isEmpty, books.count < total {
                    Text(L("\(total - books.count) more can't be moved from here and will stay")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BookRow: View {
    @Environment(AppModel.self) private var model
    let book: Book
    let shelf: Shelf
    var highlighted = false
    @State private var hover = false

    private var showEra: Bool { shelf.category != .system }

    var body: some View {
        let refusal = model.refusal(book, in: shelf)
        let keptHere = model.decisions.keptPaths.contains(book.path)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(book.kind.name).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    if book.protected { Image(systemName: "lock").font(.caption2).foregroundStyle(.tertiary).help("Needs administrator rights or is protected by macOS") }
                    if showEra, model.flaggedUnused(book, in: shelf) { Tag(L("Unused")) }
                    if keptHere { Tag(L("Kept")) }
                    if let n = itemNote {
                        if let g = n.group { Tag(g) }
                        if let a = n.suggestion { Tag(a.label, filled: a == .delete) }
                    }
                    if book.nested { Text("Inside one of the items above").font(.caption2).foregroundStyle(.tertiary) }
                }
                Text(Fmt.path(book.path))
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                if !meta.isEmpty {
                    Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                }
                if let n = itemNote {
                    Text(L("AI: \([n.owner, n.what, n.reason].compactMap { $0 }.joined(separator: " · "))"))
                        .font(.caption).lineLimit(4).textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            Text(Fmt.size(book.size)).monospacedDigit().foregroundStyle(.secondary)
            HStack(spacing: 6) {
                rowButton("arrow.forward.circle", help: L("Show in Finder")) { model.reveal(book.path) }
                if showEra {
                    rowButton("snowflake", help: refusal ?? L("Freeze"), disabled: refusal != nil) { model.request(.freeze, [book], in: shelf) }
                    rowButton("trash", help: refusal ?? L("Move to Trash"), disabled: refusal != nil) { model.request(.trash, [book], in: shelf) }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(highlighted ? 0.07 : (hover ? 0.035 : 0))))
        .onHover { hover = $0 }
        .contextMenu {
            Button("Show in Finder") { model.reveal(book.path) }
            if showEra {
                Divider()
                if CatalogReport.isCollection(shelf), model.aiReady, model.aiTargets(shelf).contains(where: { $0.key == model.aiKey(book) }) {
                    Button(itemNote == nil ? L("Ask the AI What This Is") : L("Ask the AI Again")) { model.recognise(item: book, in: shelf) }
                        .disabled(model.aiProgress != nil)
                }
                Button(keptHere ? L("Unkeep") : L("Keep, Stop Reminding Me")) { model.toggleKeep(book) }
                Button("Freeze…") { model.request(.freeze, [book], in: shelf) }.disabled(refusal != nil)
                Button("Move to Trash…") { model.request(.trash, [book], in: shelf) }.disabled(refusal != nil)
            }
        }
    }

    private var itemNote: AINote? { CatalogReport.isCollection(shelf) ? model.aiNote(book) : nil }

    private func rowButton(_ symbol: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(disabled ? 0.15 : (hover ? 1 : 0.35))
            .disabled(disabled)
            .help(help)
    }

    private var meta: String {
        var parts = [String]()
        if showEra, book.era != nil { parts.append(L("From \(model.eraName(book.era))")) }
        if let m = book.modified { parts.append(L("Changed \(Fmt.day(m))")) }
        if let u = book.lastUsed { parts.append(L("Last used \(Fmt.day(u))")) }
        var line = parts.joined(separator: " · ")
        if let n = book.note, !n.isEmpty { line += (line.isEmpty ? "" : "\n") + n }
        return line
    }
}
