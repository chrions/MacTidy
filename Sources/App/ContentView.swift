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
        .alert(trashTitle, isPresented: Binding(get: { model.trashRequest != nil }, set: { if !$0 { model.trashRequest = nil } }),
               presenting: model.trashRequest) { request in
            if request.blocked == nil {
                Button("移到废纸篓", role: .destructive) { model.confirmTrash() }
                Button("取消", role: .cancel) {}
            } else {
                Button("好", role: .cancel) {}
            }
        } message: { request in
            Text(trashMessage(request))
        }
        .overlay(alignment: .bottom) {
            if let outcome = model.trashOutcome {
                TrashBar(outcome: outcome).padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.trashOutcome == nil)
        .task { await Snapshot.runIfRequested(model) }
    }
}

extension ContentView {
    private var trashTitle: String {
        guard let r = model.trashRequest else { return "" }
        if r.blocked != nil { return "现在还不能扔" }
        return r.books.count == 1 ? "把「\((r.books[0].path as NSString).lastPathComponent)」移到废纸篓？"
            : "把「\(r.shelf.title)」的 \(r.books.count) 项移到废纸篓？"
    }

    private func trashMessage(_ r: AppModel.TrashRequest) -> String {
        if let blocked = r.blocked { return blocked }
        var lines = ["共 \(Fmt.size(r.size))。在废纸篓清倒之前随时可以放回原处。"]
        lines += r.warnings
        let paths = r.books.prefix(6).map { Fmt.path($0.path) }
        lines.append("\n" + paths.joined(separator: "\n") + (r.books.count > 6 ? "\n…等 \(r.books.count) 项" : ""))
        return lines.joined(separator: "\n")
    }
}

/// Result of the last move to the Trash, with a way to take it back.
private struct TrashBar: View {
    @Environment(AppModel.self) private var model
    let outcome: AppModel.TrashOutcome

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: outcome.failed.isEmpty ? "trash" : "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.callout.weight(.medium))
                ForEach(outcome.failed.prefix(3), id: \.path) { f in
                    Text("\(Fmt.path(f.path))：\(f.reason)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 20)
            if !outcome.moved.isEmpty {
                Button("撤销") { model.undoTrash() }
                Button("打开废纸篓") { model.openTrash() }
            }
            Button { model.trashOutcome = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private var headline: String {
        let size = outcome.moved.compactMap(\.size).reduce(0, +)
        let moved = outcome.moved.isEmpty ? "" : "已移到废纸篓 \(outcome.moved.count) 项 · \(Fmt.size(size))"
        if outcome.failed.isEmpty { return moved }
        let failed = outcome.undone ? "\(outcome.failed.count) 项没能放回" : "\(outcome.failed.count) 项没能移走"
        return moved.isEmpty ? failed : "\(moved)，\(failed)"
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
