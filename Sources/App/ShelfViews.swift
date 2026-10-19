import SwiftUI

/// List of shelves on the left, the selected shelf on the right. `category == nil` searches everything.
struct CategoryBrowser: View {
    @Environment(AppModel.self) private var model
    let category: Category?

    var body: some View {
        @Bindable var model = model
        let shelves = model.shelves(in: category)
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                header(shelves)
                Divider()
                if shelves.isEmpty {
                    ContentUnavailableView("没有符合条件的东西", systemImage: "line.3.horizontal.decrease",
                                           description: Text("试试清除筛选条件"))
                } else {
                    List(selection: $model.selectedShelf) {
                        ForEach(shelves) { s in
                            ShelfRow(shelf: s).tag(s.id)
                        }
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
            if model.isUnused(shelf) { Tag("没用过") }
            Text(Fmt.size(shelf.size)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if CatalogReport.isCollection(shelf) { return "\(model.visibleBooks(shelf).count) 项 · \(shelf.summary)" }
        return shelf.category == .system ? shelf.summary : "\(model.eraName(shelf.era)) · \(shelf.summary)"
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
                                BookRow(book: b, showEra: shelf.category != .system, highlighted: model.focusedBook == b.path)
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
        if CatalogReport.isCollection(shelf) {
            let unused = shelf.books.filter { !$0.nested && model.used($0) == false }.count
            return unused == 0 ? "都用过" : "\(unused) 项没用过"
        }
        switch shelf.usedSinceArrival {
        case true?: return "用过"
        case false?: return "没用过"
        default: return "无记录"
        }
    }
}

struct BookRow: View {
    @Environment(AppModel.self) private var model
    let book: Book
    let showEra: Bool
    var highlighted = false
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(book.kind.rawValue).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    if book.protected { Image(systemName: "lock").font(.caption2).foregroundStyle(.tertiary).help("需要管理员权限或受系统保护") }
                    if showEra, model.used(book) == false { Tag("没用过") }
                    if book.nested { Text("包含在上面某一项里").font(.caption2).foregroundStyle(.tertiary) }
                }
                Text(Fmt.path(book.path))
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                if !meta.isEmpty {
                    Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            Text(Fmt.size(book.size)).monospacedDigit().foregroundStyle(.secondary)
            Button { model.reveal(book.path) } label: {
                Image(systemName: "arrow.forward.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(hover ? 1 : 0.35)
            .help("在访达中显示")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(highlighted ? 0.07 : (hover ? 0.035 : 0))))
        .onHover { hover = $0 }
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
