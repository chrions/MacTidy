import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 230, max: 300)
        } detail: {
            Group {
                if model.catalog == nil {
                    EmptyState()
                } else {
                    switch model.sidebar {
                    case .category(let c)?:
                        CategoryBrowser(category: c)
                    case .coldRoom?:
                        ColdRoomView()
                    default:
                        if model.search.isEmpty { OverviewView() } else { CategoryBrowser(category: nil) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "搜索名称或路径")
        .toolbar { Toolbar() }
        .tint(.primary)
        .onChange(of: model.sidebar) { model.focusedBook = nil }
        .alert(pendingTitle, isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }),
               presenting: model.pending) { p in
            if p.blocked == nil {
                Button(confirmLabel(p.action), role: isDestructive(p.action) ? .destructive : nil) { model.confirm() }
                Button("取消", role: .cancel) {}
            } else {
                Button("好", role: .cancel) {}
            }
        } message: { p in
            Text(pendingMessage(p))
        }
        .overlay(alignment: .bottom) {
            if let outcome = model.outcome {
                OutcomeBar(outcome: outcome).padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.outcome == nil)
        .task { await Snapshot.runIfRequested(model) }
    }
}

extension ContentView {
    private var pendingTitle: String {
        guard let p = model.pending else { return "" }
        if p.blocked != nil { return "现在还不能挪" }
        let what = p.books.count == 1 ? "「\((p.books[0].path as NSString).lastPathComponent)」" : "「\(p.shelf.title)」的 \(p.books.count) 项"
        switch p.action {
        case .trash: return "把\(what)移到废纸篓？"
        case .freeze: return "把\(what)冷藏起来？"
        case .discard(let b): return "把冷藏的「\(b.shelf.title)」移到废纸篓？"
        }
    }

    private func confirmLabel(_ action: AppModel.Action) -> String {
        if case .freeze = action { return "冷藏" }
        return "移到废纸篓"
    }

    private func isDestructive(_ action: AppModel.Action) -> Bool {
        if case .freeze = action { return false }
        return true
    }

    private func pendingMessage(_ p: AppModel.PendingAction) -> String {
        if let blocked = p.blocked { return blocked }
        var lines: [String]
        switch p.action {
        case .trash: lines = ["共 \(Fmt.size(p.size))。在废纸篓清倒之前随时可以放回原处。"]
        case .freeze: lines = ["共 \(Fmt.size(p.size))，会挪到「\(ColdStorage.folderName)」，原来的位置都记着，随时能一键放回。"]
        case .discard(let b): lines = ["共 \(b.items.count) 项 · \(Fmt.size(b.size))，冷藏于 \(Fmt.day(b.date))。在废纸篓清倒之前还能放回冷藏区。"]
        }
        lines += p.warnings
        let paths = p.books.prefix(6).map { Fmt.path($0.path) }
        lines.append("\n" + paths.joined(separator: "\n") + (p.books.count > 6 ? "\n…等 \(p.books.count) 项" : ""))
        return lines.joined(separator: "\n")
    }
}

/// Result of the last move, with a way to take it back.
private struct OutcomeBar: View {
    @Environment(AppModel.self) private var model
    let outcome: AppModel.Outcome

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: outcome.failed.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.message).font(.callout.weight(.medium))
                if outcome.failed.count > 0 {
                    ForEach(outcome.failed.prefix(3), id: \.path) { f in
                        Text("\(Fmt.path(f.path))：\(f.reason)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if outcome.failed.count > 3 {
                        Text("…另有 \(outcome.failed.count - 3) 项").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 20)
            if let undo = outcome.undo {
                Button("撤销") { model.undo() }
                switch undo {
                case .trash: Button("打开废纸篓") { model.openTrash() }
                case .freeze: Button("查看冷藏区") { model.sidebar = .coldRoom; model.outcome = nil }
                }
            }
            Button { model.outcome = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 680)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            SidebarRow(item: .overview, title: "概览", symbol: "square.grid.2x2", size: nil)
            SwiftUI.Section("目录") {
                ForEach(Category.allCases, id: \.self) { c in
                    SidebarRow(item: .category(c), title: c.rawValue, symbol: c.symbol,
                               size: model.catalog == nil ? nil : model.size(of: c))
                }
            }
            SwiftUI.Section("整理") {
                SidebarRow(item: .coldRoom, title: "冷藏区", symbol: "snowflake",
                           size: model.coldBatches.isEmpty ? nil : model.coldSize)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { ScanStatus().padding(12) }
    }
}

/// The system sidebar selection always uses the accent color; draw a neutral one instead.
private struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    let item: SidebarItem
    let title: String
    let symbol: String
    let size: Int64?

    var body: some View {
        let selected = model.sidebar == item
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18)
            Text(title)
            Spacer()
            if let size {
                Text(Fmt.size(size)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .fontWeight(selected ? .semibold : .regular)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selected ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { model.sidebar = item }
        .listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
    }
}

private struct ScanStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if model.scanning {
                ProgressView().controlSize(.small)
                Text("正在扫描：\(model.progress)").lineLimit(1)
            } else if let c = model.catalog {
                Text("扫描于 \(c.generatedAt.formatted(.dateTime.month().day().hour().minute()))")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct Toolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("年代", selection: $model.eraFilter) {
                    Text("全部年代").tag(Int?.none)
                    Divider()
                    ForEach(model.eras, id: \.index) { e in
                        Text(e.name).tag(Int?.some(e.index))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(model.eraFilter.map { model.eraName($0) } ?? "全部年代", systemImage: "clock.arrow.circlepath")
                    .labelStyle(.titleAndIcon)
            }
            .help("只看某台 Mac 时期来的东西")

            Toggle(isOn: $model.onlyUnused) {
                Label("只看没用过", systemImage: "moon.zzz")
            }
            .help("只看搬到这台 Mac 后没用过的东西")

            Button {
                model.scan()
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(model.scanning)
            .help("重新扫描这台 Mac（只读，约一两分钟）")
        }
    }
}

private struct EmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical").font(.system(size: 48, weight: .light))
            VStack(spacing: 6) {
                Text("给这台 Mac 编个目录").font(.title2.weight(.semibold))
                Text("看看每样东西属于谁、来自哪台 Mac、搬过来以后用过没有。\n只读扫描，不会改动任何文件。")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            if model.scanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.progress).foregroundStyle(.secondary)
                }
            } else {
                Button("开始扫描") { model.scan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(40)
    }
}
