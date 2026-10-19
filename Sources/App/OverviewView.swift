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
        VStack(alignment: .leading, spacing: 6) {
            Text("这台 Mac").font(.system(size: 34, weight: .semibold))
            let total = catalog.shelves.map(\.size).reduce(0, +)
            let name = catalog.eras.first(where: \.isCurrent)?.name ?? catalog.machine
            Text("\(name) · 已编目 \(Fmt.size(total)) · \(catalog.shelves.count) 个书架 · 扫描于 \(Fmt.day(catalog.generatedAt))")
                .foregroundStyle(.secondary)
        }
    }

    private var accessHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
            VStack(alignment: .leading, spacing: 2) {
                Text("授予「完全磁盘访问权限」后，统计会更完整").font(.callout.weight(.medium))
                Text("部分应用的数据受系统保护，现在只能看到名字，算不出大小。").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("打开设置") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "目录")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Category.allCases, id: \.self) { c in
                    CategoryCard(category: c)
                }
            }
        }
    }

    private var unpacked: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "搬来后没用过", subtitle: "从旧 Mac 迁移过来以后，再也没有打开或改动过。最值得先看看。")
            let list = Array(model.units.filter { model.flaggedUnused($0) }.sorted { $0.size > $1.size }.prefix(12))
            if list.isEmpty {
                Text("没有发现").foregroundStyle(.secondary)
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
                    Text(category.rawValue).font(.headline)
                    Text(category.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                }
                Text(Fmt.size(model.size(of: category))).font(.title2.weight(.medium)).monospacedDigit()
                Text("\(list.count) 个书架").font(.caption).foregroundStyle(.secondary)
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
                    Text("来自 \(model.eraName(unit.era)) · 最后动静 \(Fmt.day(unit.lastActive))")
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

    var body: some View {
        let eras = model.eras
        let units = model.units
        let sizes = eras.map { e in units.filter { $0.era == e.index }.map(\.size).reduce(0, +) }
        let total = max(sizes.reduce(0, +), 1)
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "年代", subtitle: "每样东西按它最早出现的时间，归到当时在用的那台 Mac。")
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(eras.enumerated()), id: \.offset) { i, e in
                        let w = max(geo.size.width * CGFloat(sizes[i]) / CGFloat(total) - 2, sizes[i] > 0 ? 3 : 0)
                        Rectangle().fill(.primary.opacity(eraShade(i, count: eras.count))).frame(width: w)
                            .help("\(e.name)：\(Fmt.size(sizes[i]))")
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
                            Text(e.name).font(.callout.weight(.medium))
                            if e.isCurrent { Tag("现在") }
                        }
                        Text(e.start.map { "\(Fmt.month($0)) 起" } ?? e.end.map { "\(Fmt.month($0)) 以前" } ?? "第一台 Mac 之前").font(.caption).foregroundStyle(.secondary)
                        Text("\(list.count) 样 · \(Fmt.size(sizes[i]))").font(.caption).monospacedDigit()
                        if !e.isCurrent, !unused.isEmpty {
                            Text("没用过 \(unused.count) 样 · \(Fmt.size(unused.map(\.size).reduce(0, +)))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
