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
            Text("Cold Storage").font(.system(size: 34, weight: .semibold))
            Text("Things you're unsure about wait here. Where they came from is recorded, so they can go back anytime. Anything you haven't missed for half a year can usually be deleted.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(Fmt.path(ColdStorage.root)).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                Button("Show in Finder") { model.openColdRoom() }.buttonStyle(.borderless).foregroundStyle(.primary).underline()
            }
            .padding(.top, 2)
        }
    }

    private var frozen: some View {
        VStack(alignment: .leading, spacing: 14) {
            let stale = model.coldBatches.filter(\.isStale)
            SectionTitle(title: L("Frozen"),
                         subtitle: model.coldBatches.isEmpty ? nil
                         : stale.isEmpty ? L("\(model.coldBatches.count) batches · \(Fmt.size(model.coldSize))")
                         : L("\(model.coldBatches.count) batches · \(Fmt.size(model.coldSize)), \(stale.count) older than half a year"))
            if model.coldBatches.isEmpty {
                Text("Nothing frozen yet. Click Freeze on any shelf to move things here.").foregroundStyle(.secondary)
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
            SectionTitle(title: L("In the Trash"), subtitle: L("What MacTidy moved to the Trash that hasn't been emptied yet. Once the Trash is emptied, it's gone."))
            VStack(spacing: 0) {
                ForEach(Array(model.trashed.enumerated()), id: \.element.trashedTo) { i, r in
                    if i > 0 { Divider() }
                    ItemRow(title: r.shelf, path: r.path, detail: L("Trashed \(Fmt.day(r.date))"), size: r.size) {
                        Button("Put Back") { model.restore([r]) }
                    }
                }
            }
        }
    }

    private var kept: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: L("Kept"), subtitle: L("These are no longer marked as unused."))
            VStack(spacing: 0) {
                let shelves = model.decisions.keptShelves.sorted()
                let paths = model.decisions.keptPaths.sorted()
                ForEach(Array(shelves.enumerated()), id: \.element) { i, id in
                    if i > 0 { Divider() }
                    let s = model.shelf(id)
                    ItemRow(title: s?.title ?? id, path: nil, detail: s.map { L("Whole shelf · \($0.category.name)") } ?? L("Whole shelf"), size: s?.size) {
                        Button("Unkeep") { model.unkeep(shelfID: id) }
                    }
                }
                ForEach(Array(paths.enumerated()), id: \.element) { i, path in
                    if i > 0 || !shelves.isEmpty { Divider() }
                    ItemRow(title: (path as NSString).lastPathComponent, path: path, detail: nil, size: nil) {
                        Button("Unkeep") { model.unkeep(path: path) }
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
                        if batch.isStale { Tag(L("Over half a year; can go"), filled: true) }
                    }
                    Text(L("\(batch.shelf.category.name) · \(batch.items.count) items · frozen \(Fmt.day(batch.date)), \(batch.days) days ago"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(Fmt.size(batch.size)).monospacedDigit().foregroundStyle(.secondary)
                Button("Put Back") { model.thaw(batch) }
                Button("Move to Trash…") { model.request(.discard(batch), batch.items.map(\.book), in: batch.shelf) }
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
