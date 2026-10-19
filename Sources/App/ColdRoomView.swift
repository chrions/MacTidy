import SwiftUI

/// Everything MacTidy moved away or was told to keep, with the way back.
struct ColdRoomView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                frozen
                if !model.trashed.isEmpty { trashed }
                if !model.decisions.keptShelves.isEmpty || !model.decisions.keptPaths.isEmpty { kept }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 36)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.refreshShelves() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("冷藏区").font(.system(size: 34, weight: .semibold))
            Text("拿不准的东西先挪到这里，原来的位置都记着，随时能放回。冷藏半年都没想起来的，一般就可以放心删了。")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(Fmt.path(ColdStorage.root)).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                Button("在访达中显示") { model.openColdRoom() }.buttonStyle(.borderless).foregroundStyle(.primary).underline()
            }
            .padding(.top, 2)
        }
    }

    private var frozen: some View {
        VStack(alignment: .leading, spacing: 14) {
            let stale = model.coldBatches.filter(\.isStale)
            SectionTitle(title: "冷藏中",
                         subtitle: model.coldBatches.isEmpty ? nil
                         : "\(model.coldBatches.count) 批 · \(Fmt.size(model.coldSize))" + (stale.isEmpty ? "" : "，其中 \(stale.count) 批已超过半年"))
            if model.coldBatches.isEmpty {
                Text("还没有冷藏的东西。在任意书架里点「冷藏」就会挪到这里。").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.coldBatches.enumerated()), id: \.element.id) { i, b in
                        if i > 0 { Divider() }
                        BatchRow(batch: b)
                    }
                }
            }
        }
    }

    private var trashed: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "废纸篓里的", subtitle: "MacTidy 移到废纸篓、还没清倒的东西。清倒废纸篓后就找不回了。")
            VStack(spacing: 0) {
                ForEach(Array(model.trashed.enumerated()), id: \.element.trashedTo) { i, r in
                    if i > 0 { Divider() }
                    ItemRow(title: r.shelf, path: r.path, detail: "扔于 \(Fmt.day(r.date))", size: r.size) {
                        Button("放回") { model.restore([r]) }
                    }
                }
            }
        }
    }

    private var kept: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "已保留", subtitle: "这些东西不会再标「没用过」。")
            VStack(spacing: 0) {
                let shelves = model.decisions.keptShelves.sorted()
                let paths = model.decisions.keptPaths.sorted()
                ForEach(Array(shelves.enumerated()), id: \.element) { i, id in
                    if i > 0 { Divider() }
                    let s = model.shelf(id)
                    ItemRow(title: s?.title ?? id, path: nil, detail: s.map { "整个书架 · \($0.category.rawValue)" } ?? "整个书架", size: s?.size) {
                        Button("取消保留") { model.unkeep(shelfID: id) }
                    }
                }
                ForEach(Array(paths.enumerated()), id: \.element) { i, path in
                    if i > 0 || !shelves.isEmpty { Divider() }
                    ItemRow(title: (path as NSString).lastPathComponent, path: path, detail: nil, size: nil) {
                        Button("取消保留") { model.unkeep(path: path) }
                    }
                }
            }
        }
    }
}

private struct BatchRow: View {
    @Environment(AppModel.self) private var model
    let batch: ColdBatch
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 12)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(batch.shelf.title).font(.body.weight(.medium))
                        if batch.isStale { Tag("超过半年，可以删了", filled: true) }
                    }
                    Text("\(batch.shelf.category.rawValue) · \(batch.items.count) 项 · 冷藏于 \(Fmt.day(batch.date))，已 \(batch.days) 天")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(Fmt.size(batch.size)).monospacedDigit().foregroundStyle(.secondary)
                Button("放回") { model.thaw(batch) }
                Button("移到废纸篓") { model.request(.discard(batch), batch.items.map(\.book), in: batch.shelf) }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(batch.items, id: \.stored) { item in
                        HStack {
                            Text(Fmt.path(item.book.path)).font(.system(.caption, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            Spacer()
                            Text(Fmt.size(item.book.size)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }
}

private struct ItemRow<Actions: View>: View {
    let title: String
    let path: String?
    let detail: String?
    let size: Int64?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                if let path {
                    Text(Fmt.path(path)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 12)
            if let size { Text(Fmt.size(size)).monospacedDigit().foregroundStyle(.secondary) }
            actions()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }
}
