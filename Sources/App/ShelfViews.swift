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
                    ContentUnavailableView("没有符合条件的东西", systemImage: "line.3.horizontal.decrease",
                                           description: Text("试试清除筛选条件"))
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
                    ContentUnavailableView("选择一个书架", systemImage: "books.vertical")
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ shelves: [Shelf]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category?.rawValue ?? "搜索结果").font(.title2.weight(.semibold))
            Text(category?.blurb ?? "名称、说明或路径里包含「\(model.search)」").font(.callout).foregroundStyle(.secondary)
            Text("\(shelves.count) 个书架 · \(Fmt.size(shelves.map(\.size).reduce(0, +)))")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit().padding(.top, 2)
            if category == .orphans || category == .personal {
                let pending = model.aiPendingCount(shelves)
                if pending > 0 {
                    AIButton(title: "用 AI 识别这一类（\(pending) 项）") { model.requestRecognition(shelves) }
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
        if model.isKept(shelf) { return "已保留" }
        guard CatalogReport.isCollection(shelf) else { return shelf.usedSinceArrival == false ? "没用过" : nil }
        let (unused, total) = model.unusedCount(shelf)
        if unused == 0 { return nil }
        return unused == total ? "没用过" : "\(unused) 项没用过"
    }

    private var subtitle: String {
        if CatalogReport.isCollection(shelf) { return "\(model.visibleBooks(shelf).count) 项 · \(shelf.summary)" }
        let summary = model.aiNote(shelf).map { "AI：" + ($0.owner ?? $0.what) } ?? shelf.summary
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
                        Text(shelf.category.rawValue).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(shelf.title).font(.system(size: 26, weight: .semibold)).textSelection(.enabled)
                        Text(shelf.summary).foregroundStyle(.secondary)
                    }

                    ShelfActions(shelf: shelf)

                    AICard(shelf: shelf)

                    HStack(alignment: .top, spacing: 16) {
                        Fact(label: "大小", value: Fmt.size(shelf.size))
                        if shelf.category != .system {
                            Fact(label: "来自", value: model.eraName(shelf.era))
                            Fact(label: "最后动静", value: Fmt.day(shelf.lastActive))
                            Fact(label: "搬来后", value: usedText)
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
                        SectionTitle(title: "存放位置", subtitle: books.count == shelf.books.count ? "\(books.count) 处"
                                     : "\(books.count) 处符合筛选（共 \(shelf.books.count) 处）")
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
        if model.isKept(shelf) { return "已保留" }
        if CatalogReport.isCollection(shelf) {
            let (unused, total) = model.unusedCount(shelf)
            return unused == 0 ? "都用过" : unused == total ? "都没用过" : "\(unused) 项没用过"
        }
        switch shelf.usedSinceArrival {
        case true?: return "用过"
        case false?: return "没用过"
        default: return "无记录"
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
            SettingsLink { Label("设置 AI 识别…", systemImage: "sparkles") }
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
                        AIButton(title: "用 AI 识别这 \(pending) 项") { model.requestRecognition([shelf]) }
                    }
                    if pending < targets.count {
                        Text("已识别 \(targets.count - pending) 项，结果在下面每一项里").font(.caption).foregroundStyle(.secondary)
                        Button("全部重新识别") { model.recognise([shelf], force: true) }
                            .buttonStyle(.borderless).font(.caption).disabled(model.aiProgress != nil)
                    }
                    let withheld = model.aiWithheld(shelf)
                    if withheld > 0 {
                        Text("\(withheld) 项名字像证件、合同或密钥，不发给 AI").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if let note = model.aiNote(shelf) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.caption)
                        Text("AI 识别").font(.caption.weight(.medium))
                        if let advice = note.advice { Tag("建议\(advice)", filled: advice == "可以删") }
                        Spacer()
                        Button("重新识别") { model.recognise([shelf], force: true) }
                            .buttonStyle(.borderless).font(.caption).disabled(model.aiProgress != nil)
                    }
                    .foregroundStyle(.secondary)
                    if let owner = note.owner { Text(owner).font(.headline) }
                    Text(note.what).textSelection(.enabled)
                    if let reason = note.reason { Text(reason).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                    Text("\(note.model) · \(Fmt.day(note.date)) · 仅根据名称和路径推断，供参考")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.04)))
            } else {
                AIButton(title: "问问 AI 这是什么") { model.recognise([shelf]) }
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
            let scope = collection ? "没用过的 \(books.count) 项" : "全部"
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button { model.toggleKeep(shelf) } label: {
                        Label(kept ? "取消保留" : "保留", systemImage: kept ? "pin.slash" : "pin")
                    }
                    .help(kept ? "重新提醒这个书架里没用过的东西" : "以后不再提醒这个书架没用过")
                    if !books.isEmpty {
                        Button { model.request(.freeze, books, in: shelf) } label: {
                            Label("冷藏\(scope)", systemImage: "snowflake")
                        }
                        .help("挪到冷藏区，随时能放回")
                        Button(role: .destructive) { model.request(.trash, books, in: shelf) } label: {
                            Label("\(scope)移到废纸篓", systemImage: "trash")
                        }
                    }
                }
                .buttonStyle(.bordered)
                if !books.isEmpty, books.count < total {
                    Text("另有 \(total - books.count) 处不能从这里挪，会留着").font(.caption).foregroundStyle(.secondary)
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
                    Text(book.kind.rawValue).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    if book.protected { Image(systemName: "lock").font(.caption2).foregroundStyle(.tertiary).help("需要管理员权限或受系统保护") }
                    if showEra, model.flaggedUnused(book, in: shelf) { Tag("没用过") }
                    if keptHere { Tag("已保留") }
                    if let n = itemNote {
                        if let g = n.group { Tag(g) }
                        if let a = n.advice { Tag("建议\(a)", filled: a == "可以删") }
                    }
                    if book.nested { Text("包含在上面某一项里").font(.caption2).foregroundStyle(.tertiary) }
                }
                Text(Fmt.path(book.path))
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                if !meta.isEmpty {
                    Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                }
                if let n = itemNote {
                    Text("AI：" + [n.owner, n.what, n.reason].compactMap { $0 }.joined(separator: "。"))
                        .font(.caption).lineLimit(4).textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            Text(Fmt.size(book.size)).monospacedDigit().foregroundStyle(.secondary)
            HStack(spacing: 6) {
                rowButton("arrow.forward.circle", help: "在访达中显示") { model.reveal(book.path) }
                if showEra {
                    rowButton("snowflake", help: refusal ?? "冷藏", disabled: refusal != nil) { model.request(.freeze, [book], in: shelf) }
                    rowButton("trash", help: refusal ?? "移到废纸篓", disabled: refusal != nil) { model.request(.trash, [book], in: shelf) }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(highlighted ? 0.07 : (hover ? 0.035 : 0))))
        .onHover { hover = $0 }
        .contextMenu {
            Button("在访达中显示") { model.reveal(book.path) }
            if showEra {
                Divider()
                if CatalogReport.isCollection(shelf), model.aiReady, model.aiTargets(shelf).contains(where: { $0.key == model.aiKey(book) }) {
                    Button(itemNote == nil ? "问问 AI 这是什么" : "让 AI 重新识别") { model.recognise(item: book, in: shelf) }
                        .disabled(model.aiProgress != nil)
                }
                Button(keptHere ? "取消保留" : "保留，不再提醒") { model.toggleKeep(book) }
                Button("冷藏") { model.request(.freeze, [book], in: shelf) }.disabled(refusal != nil)
                Button("移到废纸篓") { model.request(.trash, [book], in: shelf) }.disabled(refusal != nil)
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
        if showEra, book.era != nil { parts.append("来自 \(model.eraName(book.era))") }
        if let m = book.modified { parts.append("改动于 \(Fmt.day(m))") }
        if let u = book.lastUsed { parts.append("最后使用 \(Fmt.day(u))") }
        var line = parts.joined(separator: " · ")
        if let n = book.note, !n.isEmpty { line += (line.isEmpty ? "" : "\n") + n }
        return line
    }
}
