import Foundation

struct Report {
    let ctx: Context
    let items: [Item]

    private func cell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    private func total(_ list: [Item]) -> Int64 { list.compactMap(\.size).reduce(0, +) }

    func markdown() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var md = "# Mac 梳理报告\n\n"
        md += "- 生成时间：\(f.string(from: ctx.now))\n"
        md += "- 「很久没用」的标准：超过 **\(ctx.staleDays) 天**\n"
        md += "- 命令使用时间来自 `~/.zsh_history`，记录始于 \(formatAge(ctx.history.earliest, now: ctx.now))\n"
        md += "- **只读扫描，没有修改或删除任何文件。** 「建议」一列只是提示，请确认后自己执行。\n\n"

        md += "## 概览\n\n| 类别 | 项目数 | 🟢 可清理 | 🟡 看情况 | ⚪️ 待识别 |\n|---|---:|---:|---:|---:|\n"
        for section in Section.allCases {
            let list = items.filter { $0.section == section }
            guard !list.isEmpty else { continue }
            func col(_ v: Verdict) -> String {
                let l = list.filter { $0.verdict == v }
                return l.isEmpty ? "—" : "\(l.count) 项 / \(formatSize(total(l)))"
            }
            md += "| \(section.rawValue) | \(list.count) | \(col(.clean)) | \(col(.review)) | \(col(.unknown)) |\n"
        }
        let clean = items.filter { $0.verdict == .clean }
        let review = items.filter { $0.verdict == .review }
        md += "\n**可直接清理约 \(formatSize(total(clean)))；看情况再清理约 \(formatSize(total(review)))。**"
        md += "（各类别可能有少量重叠，例如某个隐藏目录本身和它里面的缓存。）\n\n"

        let biggest = (clean + review).filter { ($0.size ?? 0) > 0 }.sorted { ($0.size ?? 0) > ($1.size ?? 0) }.prefix(15)
        if !biggest.isEmpty {
            md += "### 最占空间的 15 项\n\n| 结论 | 名称 | 类别 | 大小 | 原因 |\n|---|---|---|---:|---|\n"
            for i in biggest {
                md += "| \(i.verdict.badge) | \(cell(i.name)) | \(i.section.rawValue) | \(formatSize(i.size)) | \(cell(i.reason)) |\n"
            }
            md += "\n"
        }

        for (n, section) in Section.allCases.enumerated() {
            let list = items.filter { $0.section == section }
            guard !list.isEmpty else { continue }
            md += "## \(n + 1). \(section.rawValue)\n\n"
            let sorted = list.sorted {
                $0.verdict.order != $1.verdict.order ? $0.verdict.order < $1.verdict.order : ($0.size ?? 0) > ($1.size ?? 0)
            }
            let active = sorted.filter { $0.verdict != .keep }
            let kept = sorted.filter { $0.verdict == .keep }
            if active.isEmpty {
                md += "没有需要处理的项目。\n\n"
            } else {
                md += table(active)
            }
            if !kept.isEmpty {
                md += "<details><summary>保留的 \(kept.count) 项（\(formatSize(total(kept)))）</summary>\n\n" + table(kept) + "</details>\n\n"
            }
        }

        md += """
        ## 判断依据和局限

        - **应用**：看 Spotlight 记录的「上次打开时间」。从程序坞或启动台打开都会记录；只在后台运行的应用可能显示没有记录。
        - **命令行工具**：看 `~/.zsh_history` 里最后一次调用的时间。被脚本、IDE 或其他程序间接调用不会留下记录，所以「没用过」不等于「没被依赖」。
        - **隐藏文件**：先用内置知识库认出它属于哪个软件，再看这个软件还在不在；时间用的是目录里最新的修改时间。
        - **软件残留**：按文件夹名（bundle ID）匹配已安装的应用，匹配不上就算疑似残留。同一厂商的其他应用还在时，会保守地当作还在用。
        - **没扫描的地方**：桌面、文稿、下载（需要单独授权），系统级的登录项（需要管理员权限），以及容器目录的大小。

        """
        return md
    }

    private func table(_ list: [Item]) -> String {
        var t = "| 结论 | 名称 | 大小 | 最近使用 | 是什么 / 为什么 | 建议 |\n|---|---|---:|---|---|---|\n"
        for i in list {
            let name = "**\(cell(i.name))**" + (i.path.map { "<br>`\(cell(abbreviate($0, home: ctx.home)))`" } ?? "")
            let what = [i.detail, i.reason].filter { !$0.isEmpty }.joined(separator: "。")
            t += "| \(i.verdict.badge) | \(name) | \(formatSize(i.size)) | \(formatAge(i.lastUsed, now: ctx.now)) | \(cell(what)) | \(cell(i.suggestion ?? "")) |\n"
        }
        return t + "\n"
    }

    func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(items)
    }
}
