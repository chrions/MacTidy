import Foundation

func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

struct CatalogReport {
    let catalog: Catalog
    let home: String

    private var arrival: Date? { catalog.eras.first(where: \.isCurrent)?.start }

    func eraName(_ index: Int?) -> String {
        guard let index, let era = catalog.eras.first(where: { $0.index == index }) else { return L("Unknown") }
        return era.name
    }

    private func day(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func usedText(_ s: Shelf) -> String {
        switch s.usedSinceArrival {
        case true?: return "used since arriving"
        case false?: return "**not used since arriving**"
        default: return "no record of use"
        }
    }

    /// Something the user would think of as one thing: an app's shelf, or a single book on a collection shelf.
    struct Unit {
        var shelfID: String
        var bookPath: String?
        var category: Category
        var title: String
        var size: Int64
        var era: Int?
        var lastActive: Date?
        var used: Bool?
    }

    /// Shelves that gather unrelated books (personal files, a toolchain's versions, shell config).
    static func isCollection(_ s: Shelf) -> Bool {
        s.category == .personal || ["term:", "tool:", "orphan:tiny"].contains { s.id.hasPrefix($0) }
    }

    var units: [Unit] {
        let threshold = arrival?.addingTimeInterval(86_400)
        return catalog.shelves.filter { $0.category != .system }.flatMap { s -> [Unit] in
            guard CatalogReport.isCollection(s) else {
                return [Unit(shelfID: s.id, category: s.category, title: s.title, size: s.size, era: s.era,
                             lastActive: s.lastActive, used: s.usedSinceArrival)]
            }
            return s.books.filter { !$0.nested }.map { b in
                Unit(shelfID: s.id, bookPath: b.path, category: s.category, title: L("\(s.title): \(abbreviate(b.path, home: home))"),
                     size: b.size ?? 0, era: b.era,
                     lastActive: b.activity, used: b.idle ? false : zip2(b.activity, threshold).map { $0 >= $1 })
            }
        }
    }

    /// Unused since moving to this Mac, biggest first: the boxes that were never unpacked.
    var unpacked: [Unit] {
        units.filter { $0.used == false }.sorted { $0.size > $1.size }
    }

    func summary() -> String {
        var out = ["Eras (from when each Mac first logged in):"]
        let all = units
        for era in catalog.eras {
            let list = all.filter { $0.era == era.index }
            guard era.start != nil || !list.isEmpty else { continue }
            let range = era.start.map { "from \(day($0))" } ?? "earliest"
            let unused = list.filter { $0.used == false }
            out.append("  \(era.name) (\(range)): \(list.count) items, \(formatSize(list.map(\.size).reduce(0, +)))"
                       + (era.isCurrent ? "" : "; \(unused.count) not used since arriving, \(formatSize(unused.map(\.size).reduce(0, +)))"))
        }
        out.append("")
        out.append("Catalog:")
        for c in Category.allCases {
            let list = catalog.shelves.filter { $0.category == c }
            let unused = all.filter { $0.category == c && $0.used == false }
            var line = "  \(c.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(list.count) shelves, \(formatSize(list.map(\.size).reduce(0, +)))"
            if !unused.isEmpty { line += "; \(unused.count) not used since arriving, \(formatSize(unused.map(\.size).reduce(0, +)))" }
            out.append(line)
        }
        out.append("")
        out.append("Never used since moving to this Mac (20 biggest):")
        for u in unpacked.prefix(20) {
            out.append("  [\(u.category.name)] \(u.title)  \(formatSize(u.size))  from \(eraName(u.era)), last activity \(day(u.lastActive))")
        }
        return out.joined(separator: "\n")
    }

    func markdown() -> String {
        var md = ["# Mac library catalog", ""]
        md.append("Generated \(day(catalog.generatedAt)) · Machine: \(catalog.machine)")
        md.append("")
        md.append("## Eras")
        md.append("")
        md.append("| Era | From | Until | Items from this era | Size | Not used since arriving |")
        md.append("|---|---|---|---|---|---|")
        let all = units
        for era in catalog.eras {
            let list = all.filter { $0.era == era.index }
            let unused = list.filter { $0.used == false }
            md.append("| \(era.name) | \(day(era.start)) | \(era.end.map(day) ?? "now") | \(list.count) | \(formatSize(list.map(\.size).reduce(0, +))) | "
                      + (era.isCurrent ? "—" : "\(unused.count), \(formatSize(unused.map(\.size).reduce(0, +)))") + " |")
        }
        md.append("")
        md.append("## Not used since arriving")
        md.append("")
        md.append("Never opened or changed since being migrated from an older Mac. The best place to start.")
        md.append("")
        md.append("| Category | Name | Size | From | Last activity |")
        md.append("|---|---|---|---|---|")
        for u in unpacked.prefix(80) {
            md.append("| \(u.category.name) | \(u.title) | \(formatSize(u.size)) | \(eraName(u.era)) | \(day(u.lastActive)) |")
        }
        for c in Category.allCases {
            let list = catalog.shelves.filter { $0.category == c }.sorted { $0.size > $1.size }
            guard !list.isEmpty else { continue }
            md.append("")
            md.append("## \(c.name) (\(list.count) shelves, \(formatSize(list.map(\.size).reduce(0, +))))")
            md.append("")
            md.append(c.blurb)
            for s in list {
                md.append("")
                var head = "### \(s.title) · \(formatSize(s.size))"
                if c != .system { head += " · from \(eraName(s.era)) · \(usedText(s))" }
                md.append(head)
                md.append("")
                var meta = [s.summary]
                if !s.flags.isEmpty { meta.append(s.flags.joined(separator: ", ")) }
                if let lu = s.lastUsed { meta.append("last opened \(day(lu))") }
                if let r = s.reason { meta.append(r) }
                md.append(meta.joined(separator: ". "))
                md.append("")
                let shown = s.books.prefix(12)
                for b in shown {
                    var line = "- \(b.kind.name): `\(abbreviate(b.path, home: home))` · \(formatSize(b.size))"
                    if let e = b.era, c != .system { line += " · \(eraName(e))" }
                    if let m = b.modified { line += " · changed \(day(m))" }
                    if b.protected { line += " · 🔒" }
                    if let n = b.note, !n.isEmpty { line += " — \(n)" }
                    md.append(line)
                }
                if s.books.count > shown.count { md.append("- … and \(s.books.count - shown.count) more") }
            }
        }
        md.append("")
        md.append("## Notes")
        md.append("")
        catalog.notes.forEach { md.append("- \($0)") }
        return md.joined(separator: "\n")
    }

    func json() throws -> Data {
        try CatalogStore.encode(catalog)
    }
}
