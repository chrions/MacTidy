import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let catalog = model.catalog {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header(catalog)
                    if !model.hasFullDiskAccess { accessHint }
                    EraTimeline()
                    categories
                    unpacked
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 36)
                .frame(maxWidth: 960, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func header(_ catalog: Catalog) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("This Mac").font(.system(size: 34, weight: .semibold))
                let total = catalog.shelves.map(\.size).reduce(0, +)
                let name = catalog.eras.first(where: \.isCurrent)?.name ?? catalog.machine
                Text(L("\(name) · \(Fmt.size(total)) catalogued · \(catalog.shelves.count) shelves · scanned \(Fmt.day(catalog.generatedAt))"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button { model.scan() } label: {
                    Label(model.scanning ? L("Scanning…") : L("Scan Whole Mac"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.scanning)
                .help("Take stock of the whole Mac again; read-only, usually a minute or two")
                if model.scanning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(model.progress).lineLimit(1)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: 220, alignment: .trailing)
                }
            }
            .padding(.top, 8)
        }
    }

    private var accessHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
            VStack(alignment: .leading, spacing: 2) {
                Text("Grant Full Disk Access for a more complete catalog").font(.callout.weight(.medium))
                Text("Some apps' data is protected by macOS; for now only names are visible, not sizes.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: L("Catalog"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Category.allCases, id: \.self) { c in
                    CategoryCard(category: c)
                }
            }
        }
    }

    private var unpacked: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: L("Not Used Since Arriving"), subtitle: L("Never opened or changed since being migrated from an older Mac. The best place to start."))
            let list = Array(model.units.filter { model.flaggedUnused($0) }.sorted { $0.size > $1.size }.prefix(12))
            if list.isEmpty {
                Text("Nothing found").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, unit in
                        if i > 0 { Divider() }
                        UnitRow(unit: unit)
                    }
                }
            }
        }
    }
}

private struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let category: Category
    @State private var hover = false

    var body: some View {
        let list = model.catalog?.shelves.filter { $0.category == category } ?? []
        Button {
            model.sidebar = .category(category)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: category.symbol).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name).font(.headline)
                    Text(category.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                }
                Text(Fmt.size(model.size(of: category))).font(.title2.weight(.medium)).monospacedDigit()
                Text(L("\(list.count) shelves")).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(hover ? 0.06 : 0.03)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct UnitRow: View {
    @Environment(AppModel.self) private var model
    let unit: CatalogReport.Unit
    @State private var hover = false

    var body: some View {
        Button { model.open(unit) } label: {
            HStack(spacing: 12) {
                Image(systemName: unit.category.symbol).foregroundStyle(.secondary).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.title).lineLimit(1).truncationMode(.middle)
                    Text(L("From \(model.eraName(unit.era)) · last activity \(Fmt.day(unit.lastActive))"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Fmt.size(unit.size)).monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(hover ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// One bar split by era, sized by how much each Mac contributed.
struct EraTimeline: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: Era?
    @State private var newName = ""

    var body: some View {
        let eras = model.eras
        let units = model.units
        let sizes = eras.map { e in units.filter { $0.era == e.index }.map(\.size).reduce(0, +) }
        let total = max(sizes.reduce(0, +), 1)
        let migrated = eras.filter { $0.machineID != nil }.count > 1
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: L("Eras"), subtitle: migrated
                         ? L("Each thing belongs to the Mac in use when it first appeared. Click a name to call it what you remember it by.")
                         : L("No sign of migration from another Mac, so everything belongs to this one; older things came from archives, copies or backups."))
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(eras.enumerated()), id: \.offset) { i, e in
                        let w = max(geo.size.width * CGFloat(sizes[i]) / CGFloat(total) - 2, sizes[i] > 0 ? 3 : 0)
                        Rectangle().fill(.primary.opacity(eraShade(i, count: eras.count))).frame(width: w)
                            .help(L("\(e.name): \(Fmt.size(sizes[i]))"))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 14)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(eras.enumerated()), id: \.offset) { i, e in
                    let list = units.filter { $0.era == e.index }
                    let unused = list.filter { model.flaggedUnused($0) }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(eraShade(i, count: eras.count))).frame(width: 10, height: 10)
                            Button {
                                newName = e.name
                                renaming = e
                            } label: {
                                Text(e.name).font(.callout.weight(.medium)).multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                            .help("Rename it, e.g. “Intel MacBook from work”")
                            if e.isCurrent { Tag(L("Now")) }
                        }
                        Text(e.start.map { L("Since \(Fmt.month($0))") } ?? e.end.map { L("Before \(Fmt.month($0))") } ?? L("Before the first Mac")).font(.caption).foregroundStyle(.secondary)
                        Text(L("\(list.count) items · \(Fmt.size(sizes[i]))")).font(.caption).monospacedDigit()
                        if !e.isCurrent, !unused.isEmpty {
                            Text(L("\(unused.count) unused · \(Fmt.size(unused.map(\.size).reduce(0, +)))"))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .alert("Name this era", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let e = renaming { model.renameEra(e, to: newName) } }
            Button("Use Default") { if let e = renaming { model.renameEra(e, to: "") } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(renaming.map { $0.start.map { L("The Mac used from \(Fmt.month($0)).") } ?? L("Things from before the first Mac.") } ?? "")
                + Text(" ") + Text("The model and color, or whether it was from work, might help you remember.")
        }
    }
}
