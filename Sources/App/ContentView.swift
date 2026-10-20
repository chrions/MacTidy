import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 250, ideal: 260, max: 320)
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
        .searchable(text: $model.search, placement: .toolbar, prompt: Text("Search names or paths"))
        .toolbar { Toolbar() }
        .tint(.primary)
        .onChange(of: model.sidebar) { model.focusedBook = nil }
        .alert(pendingTitle, isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }),
               presenting: model.pending) { p in
            if p.blocked == nil {
                Button(confirmLabel(p.action), role: isDestructive(p.action) ? .destructive : nil) { model.confirm() }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { p in
            Text(pendingMessage(p))
        }
        .alert(L("Ask the AI about \(model.pendingRecognition?.count ?? 0) items?"),
               isPresented: Binding(get: { model.pendingRecognition != nil }, set: { if !$0 { model.pendingRecognition = nil } }),
               presenting: model.pendingRecognition) { _ in
            Button("Start") { model.confirmRecognition() }
            Button("Cancel", role: .cancel) {}
        } message: { p in
            let batches = (p.count + AIClient.batchSize - 1) / AIClient.batchSize
            Text(L("Sent to \(model.aiServiceName) in \(batches) requests. Only names, paths, kinds, sizes and dates are sent; file contents are never read.")
                 + (p.withheld > 0 ? "\n" + L("\(p.withheld) more look like ID documents, contracts or keys and won't be sent.") : ""))
        }
        .alert("AI recognition didn't work", isPresented: Binding(get: { model.aiError != nil }, set: { if !$0 { model.aiError = nil } })) {
            SettingsLink { Text("Open Settings") }
            Button("OK", role: .cancel) {}
        } message: {
            Text((model.aiError ?? "") + "\n\n" + L("Everything recognised so far has been saved."))
        }
        .overlay(alignment: .bottom) {
            if let outcome = model.outcome {
                OutcomeBar(outcome: outcome).padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.outcome == nil)
        .task { await Snapshot.runIfRequested(model, openSettings: openSettings) }
    }
}

extension ContentView {
    private var pendingTitle: String {
        guard let p = model.pending else { return "" }
        if p.blocked != nil { return L("Can't move this yet") }
        let what = p.books.count == 1 ? L("“\((p.books[0].path as NSString).lastPathComponent)”")
            : L("\(p.books.count) items from “\(p.shelf.title)”")
        switch p.action {
        case .trash: return L("Move \(what) to the Trash?")
        case .freeze: return L("Freeze \(what)?")
        case .discard(let b): return L("Move frozen “\(b.shelf.title)” to the Trash?")
        }
    }

    private func confirmLabel(_ action: AppModel.Action) -> String {
        if case .freeze = action { return L("Freeze") }
        return L("Move to Trash")
    }

    private func isDestructive(_ action: AppModel.Action) -> Bool {
        if case .freeze = action { return false }
        return true
    }

    private func pendingMessage(_ p: AppModel.PendingAction) -> String {
        if let blocked = p.blocked { return blocked }
        var lines: [String]
        switch p.action {
        case .trash: lines = [L("\(Fmt.size(p.size)) in total. Until the Trash is emptied, it can be put back anytime.")]
        case .freeze: lines = [L("\(Fmt.size(p.size)) in total, moved to “\(ColdStorage.folderName)”. Where everything came from is recorded, so it can all be put back in one click.")]
        case .discard(let b): lines = [L("\(b.items.count) items · \(Fmt.size(b.size)), frozen on \(Fmt.day(b.date)). Until the Trash is emptied, it can still go back to cold storage.")]
        }
        lines += p.warnings
        let paths = p.books.prefix(6).map { Fmt.path($0.path) }
        lines.append("\n" + paths.joined(separator: "\n") + (p.books.count > 6 ? "\n" + L("…\(p.books.count) items in all") : ""))
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
                        Text(L("\(Fmt.path(f.path)): \(f.reason)")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if outcome.failed.count > 3 {
                        Text(L("…and \(outcome.failed.count - 3) more")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 20)
            if let undo = outcome.undo {
                Button("Undo") { model.undo() }
                switch undo {
                case .trash: Button("Open Trash") { model.openTrash() }
                case .freeze: Button("Show Cold Storage") { model.sidebar = .coldRoom; model.outcome = nil }
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
            SidebarRow(item: .overview, title: L("Overview"), symbol: "square.grid.2x2", size: nil)
            SwiftUI.Section("Catalog") {
                ForEach(Category.allCases, id: \.self) { c in
                    SidebarRow(item: .category(c), title: c.name, symbol: c.symbol,
                               size: model.catalog == nil ? nil : model.size(of: c))
                }
            }
            SwiftUI.Section("Tidy Up") {
                SidebarRow(item: .coldRoom, title: L("Cold Storage"), symbol: "snowflake",
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
                Text(L("Scanning: \(model.progress)")).lineLimit(1)
            } else if let ai = model.aiProgress {
                ProgressView().controlSize(.small)
                Text(ai).lineLimit(1)
                Spacer()
                Button("Stop") { model.cancelRecognition() }.buttonStyle(.borderless).font(.caption)
            } else if let c = model.catalog {
                Text(L("Scanned \(c.generatedAt.formatted(.dateTime.month().day().hour().minute()))"))
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
                Picker("Era", selection: $model.eraFilter) {
                    Text("All eras").tag(Int?.none)
                    Divider()
                    ForEach(model.eras, id: \.index) { e in
                        Text(e.name).tag(Int?.some(e.index))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(model.eraFilter.map { model.eraName($0) } ?? L("All eras"), systemImage: "clock.arrow.circlepath")
                    .labelStyle(.titleAndIcon)
            }
            .help("Show only what came from one Mac")

            Toggle(isOn: $model.onlyUnused) {
                Label("Unused Only", systemImage: "moon.zzz")
            }
            .help("Show only what hasn't been used since moving to this Mac")

            Button {
                model.scan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.scanning)
            .help("Scan this Mac again (read-only, a minute or two)")
        }
    }
}

private struct EmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical").font(.system(size: 48, weight: .light))
            VStack(spacing: 6) {
                Text("Catalog this Mac").font(.title2.weight(.semibold))
                Text("See who owns each thing, which Mac it came from, and whether you've used it since moving here.\nThe scan is read-only and changes nothing.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            if model.scanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.progress).foregroundStyle(.secondary)
                }
            } else {
                Button("Start Scan") { model.scan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(40)
    }
}
