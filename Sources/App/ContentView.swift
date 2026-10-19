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
        .task { await Snapshot.runIfRequested(model) }
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
