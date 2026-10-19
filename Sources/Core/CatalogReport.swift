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
        guard let index, let era = catalog.eras.first(where: { $0.index == index }) else { return "不详" }
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
        case true?: return "搬来后用过"
        case false?: return "**搬来后没用过**"
        default: return "无使用记录"
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
                Unit(shelfID: s.id, bookPath: b.path, category: s.category, title: "\(s.title)：\(abbreviate(b.path, home: home))",
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
        var out = ["年代（按每台 Mac 第一次登录的时间推断）："]
        let all = units
        for era in catalog.eras {
            let list = all.filter { $0.era == era.index }
            guard era.start != nil || !list.isEmpty else { continue }
            let range = era.start.map { "\(day($0)) 起" } ?? "最早"
            let unused = list.filter { $0.used == false }
            out.append("  \(era.name)（\(range)）：\(list.count) 样东西，\(formatSize(list.map(\.size).reduce(0, +)))"
                       + (era.isCurrent ? "" : "；其中搬来后没用过 \(unused.count) 样，\(formatSize(unused.map(\.size).reduce(0, +)))"))
        }
        out.append("")
        out.append("目录：")
        for c in Category.allCases {
            let list = catalog.shelves.filter { $0.category == c }
            let unused = all.filter { $0.category == c && $0.used == false }
            var line = "  \(c.rawValue.padding(toLength: 6, withPad: "　", startingAt: 0)) \(list.count) 个书架，\(formatSize(list.map(\.size).reduce(0, +)))"
            if !unused.isEmpty { line += "；其中搬来后没用过 \(unused.count) 样，\(formatSize(unused.map(\.size).reduce(0, +)))" }
            out.append(line)
        }
        out.append("")
        out.append("搬到这台 Mac 后从没用过的（最大的 20 样）：")
        for u in unpacked.prefix(20) {
            out.append("  [\(u.category.rawValue)] \(u.title)  \(formatSize(u.size))  来自\(eraName(u.era))，最后动静 \(day(u.lastActive))")
        }
        return out.joined(separator: "\n")
    }

    func markdown() -> String {
        var md = ["# Mac 图书馆目录", ""]
        md.append("生成时间：\(day(catalog.generatedAt))　机器：\(catalog.machine)")
        md.append("")
        md.append("## 年代")
        md.append("")
        md.append("| 年代 | 开始 | 结束 | 来自这个年代的东西 | 大小 | 搬来后没用过 |")
        md.append("|---|---|---|---|---|---|")
        let all = units
        for era in catalog.eras {
            let list = all.filter { $0.era == era.index }
            let unused = list.filter { $0.used == false }
            md.append("| \(era.name) | \(day(era.start)) | \(era.end.map(day) ?? "至今") | \(list.count) 样 | \(formatSize(list.map(\.size).reduce(0, +))) | "
                      + (era.isCurrent ? "—" : "\(unused.count) 样，\(formatSize(unused.map(\.size).reduce(0, +)))") + " |")
        }
        md.append("")
        md.append("## 搬来后没用过的东西")
        md.append("")
        md.append("从旧 Mac 迁移过来以后，再也没有打开或改动过。最适合优先处理。")
        md.append("")
        md.append("| 分类 | 名称 | 大小 | 来自 | 最后动静 |")
        md.append("|---|---|---|---|---|")
        for u in unpacked.prefix(80) {
            md.append("| \(u.category.rawValue) | \(u.title) | \(formatSize(u.size)) | \(eraName(u.era)) | \(day(u.lastActive)) |")
        }
        for c in Category.allCases {
            let list = catalog.shelves.filter { $0.category == c }.sorted { $0.size > $1.size }
            guard !list.isEmpty else { continue }
            md.append("")
            md.append("## \(c.rawValue)（\(list.count) 个书架，\(formatSize(list.map(\.size).reduce(0, +)))）")
            md.append("")
            md.append(c.blurb)
            for s in list {
                md.append("")
                var head = "### \(s.title)　\(formatSize(s.size))"
                if c != .system { head += "　来自\(eraName(s.era))　\(usedText(s))" }
                md.append(head)
                md.append("")
                var meta = [s.summary]
                if !s.flags.isEmpty { meta.append(s.flags.joined(separator: "，")) }
                if let lu = s.lastUsed { meta.append("最后打开 \(day(lu))") }
                if let r = s.reason { meta.append(r) }
                md.append(meta.joined(separator: "。"))
                md.append("")
                let shown = s.books.prefix(12)
                for b in shown {
                    var line = "- \(b.kind.rawValue)：`\(abbreviate(b.path, home: home))`　\(formatSize(b.size))"
                    if let e = b.era, c != .system { line += "　\(eraName(e))" }
                    if let m = b.modified { line += "　改动于 \(day(m))" }
                    if b.protected { line += "　🔒" }
                    if let n = b.note, !n.isEmpty { line += "　— \(n)" }
                    md.append(line)
                }
                if s.books.count > shown.count { md.append("- ……还有 \(s.books.count - shown.count) 项") }
            }
        }
        md.append("")
        md.append("## 说明")
        md.append("")
        catalog.notes.forEach { md.append("- \($0)") }
        return md.joined(separator: "\n")
    }

    func json() throws -> Data {
        try CatalogStore.encode(catalog)
    }
}
