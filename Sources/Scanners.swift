import AppKit

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var lines: [String] { split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty } }
}

struct Scanners {
    let ctx: Context
    private var inv: Inventory { ctx.inventory }
    private var hist: ShellHistory { ctx.history }

    private func staleText(_ date: Date?) -> String {
        guard let date else { return "从来" }
        return "已 \(Int(ctx.now.timeIntervalSince(date) / 86_400)) 天"
    }

    /// Verdict for something whose usage is only knowable from shell history.
    private func commandVerdict(_ names: [String]) -> (Verdict, String, Date?) {
        guard !names.isEmpty else {
            return (.review, "没有可执行命令，可能是给其他程序用的库", nil)
        }
        let shown = names.prefix(3).joined(separator: "、")
        guard let use = hist.lastUse(of: names) else {
            return (.review, "命令历史里从没用过 \(shown)", nil)
        }
        if ctx.isStale(use.last) {
            return (.review, "超过 \(ctx.staleDays) 天没用过 \(shown)", use.last)
        }
        return (.keep, "最近用过（共 \(use.count) 次）", use.last)
    }

    // MARK: Apps

    func apps() -> [Item] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path })
        var items = inv.apps.map { app -> Item in
            let source = app.isAppStore ? "App Store" : (app.isApple ? "Apple" : "官网/其他")
            let detail = [app.version.map { "版本 \($0)" }, "来源：\(source)", app.useCount.map { "打开过 \($0) 次" }]
                .compactMap { $0 }.joined(separator: "，")
            let verdict: Verdict
            let reason: String
            if app.isApple {
                (verdict, reason) = (.keep, "苹果自带应用")
            } else if running.contains(URL(fileURLWithPath: app.path).standardizedFileURL.path) {
                (verdict, reason) = (.keep, "正在运行")
            } else if app.lastUsed == nil {
                (verdict, reason) = (.review, "Spotlight 没有它的打开记录，可能从没用过")
            } else if ctx.isStale(app.lastUsed) {
                (verdict, reason) = (.review, "超过 \(ctx.staleDays) 天没打开")
            } else {
                (verdict, reason) = (.keep, "最近在用")
            }
            return Item(section: .apps, name: app.name, path: app.path, lastUsed: app.lastUsed, lastUsedSource: "Spotlight",
                        detail: detail, verdict: verdict, reason: reason,
                        suggestion: verdict == .review ? "不用就拖到废纸篓，再看「软件残留」里有没有它留下的数据" : nil)
        }
        fillSizes(&items)
        return items
    }

    // MARK: Homebrew

    func brew() -> [Item] {
        guard let brewPath = inv.findCommand(["brew"]) else { return [] }
        let env = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"]
        let prefix = run(brewPath, ["--prefix"], env: env).out.trimmed
        var items = [Item]()

        for formula in run(brewPath, ["leaves"], env: env).out.lines {
            let short = (formula as NSString).lastPathComponent
            let opt = "\(prefix)/opt/\(short)"
            let bins = (children(opt + "/bin") + children(opt + "/sbin")).sorted { a, b in
                func rank(_ s: String) -> Int { s == short ? 0 : (s.contains("config") || s.hasSuffix(".sh") || s.hasSuffix(".py") ? 2 : 1) }
                return rank(a) != rank(b) ? rank(a) < rank(b) : a < b
            }
            let indirect: [String: [String]] = ["rbenv": ["ruby", "gem", "bundle", "rails"], "pyenv": ["python", "pip"],
                                                "nvm": ["node", "npm"], "imagemagick": ["magick", "convert"]]
            let (verdict, reason, last) = commandVerdict(bins + (indirect[short] ?? []))
            let reasonText = bins.isEmpty ? reason + "（用 brew uses --installed \(short) 看谁依赖它）" : reason
            items.append(Item(section: .brew, name: short, path: "\(prefix)/Cellar/\(short)", lastUsed: last, lastUsedSource: "命令历史",
                              detail: bins.isEmpty ? "主动安装的软件包" : "提供命令：\(bins.prefix(6).joined(separator: "、"))",
                              verdict: verdict, reason: reasonText, suggestion: verdict == .keep ? nil : "brew uninstall \(short)"))
        }

        for cask in run(brewPath, ["list", "--cask"], env: env).out.lines {
            let app = inv.findApp([cask, cask.replacingOccurrences(of: "-", with: " ")])
            let stale = ctx.isStale(app?.lastUsed)
            items.append(Item(section: .brew, name: "\(cask)（cask）", path: "\(prefix)/Caskroom/\(cask)", lastUsed: app?.lastUsed,
                              lastUsedSource: "Spotlight", detail: app.map { "安装的应用：\($0.name)" } ?? "图形应用",
                              verdict: stale ? .review : .keep, reason: stale ? "对应应用 \(staleText(app?.lastUsed)) 没打开" : "最近在用",
                              suggestion: stale ? "brew uninstall --cask \(cask)" : nil))
        }
        fillSizes(&items)
        if let legacy = legacyBrew(activePrefix: prefix) { items.append(legacy) }
        return items
    }

    // MARK: Other command-line tools

    /// Where a command really comes from, so a package's many commands become one item.
    private enum Origin: Hashable {
        case legacyBrew
        case app(String)
        case python
        case package(display: String, root: String)
        case single
    }

    private func origin(of target: String) -> Origin {
        if ["/Cellar/", "/opt/", "/Homebrew/", "/Caskroom/"].contains(where: { target.hasPrefix(legacyBrewPrefix + $0) }) { return .legacyBrew }
        if let r = target.range(of: ".app/") { return .app(String(target[..<r.lowerBound]) + ".app") }
        if target.contains("/Python.framework/") { return .python }
        if let r = target.range(of: "/lib/node_modules/") {
            let comps = target[r.upperBound...].split(separator: "/")
            let pkg = comps.first?.hasPrefix("@") == true ? comps.prefix(2).joined(separator: "/") : String(comps.first ?? "")
            return .package(display: "npm 全局包 \(pkg)", root: String(target[..<r.upperBound]) + pkg)
        }
        if target.hasPrefix("/usr/local/"), !target.hasPrefix("/usr/local/bin/"),
           let top = target.dropFirst("/usr/local/".count).split(separator: "/").first {
            return .package(display: "/usr/local/\(top)", root: "/usr/local/\(top)")
        }
        return .single
    }

    private var legacyBrewPrefix: String { "/usr/local" }

    func otherCLI() -> [Item] {
        struct Group { var origin: Origin; var bins: [(name: String, path: String)] = [] }
        var groups = [String: Group]()
        var order = [String]()
        var items = [Item]()

        for dir in ["/usr/local/bin", ctx.path(".local/bin"), ctx.path("go/bin"), ctx.path("bin")] {
            for name in children(dir) where !name.hasPrefix(".") {
                let full = (dir as NSString).appendingPathComponent(name)
                let link = isSymlink(full)
                let target = link ? resolvedPath(full) : full
                if link && !exists(target) {
                    let dest = (try? fm.destinationOfSymbolicLink(atPath: full)) ?? target
                    items.append(Item(section: .cli, name: name, path: full, size: 0, detail: "符号链接 → \(dest)", verdict: .clean,
                                      reason: "链接指向的程序已不存在，是卸载残留", suggestion: "rm '\(full)'"))
                    continue
                }
                guard fm.isExecutableFile(atPath: full), !isDirectory(full) else { continue }
                let o = origin(of: target)
                if o == .legacyBrew || o == .python { continue }
                let key: String
                switch o {
                case .app(let p): key = "app:" + p
                case .package(_, let root): key = "pkg:" + root
                default: key = "file:" + full
                }
                if groups[key] == nil { groups[key] = Group(origin: o); order.append(key) }
                groups[key]!.bins.append((name, full))
            }
        }

        for key in order {
            let g = groups[key]!
            let names = g.bins.map(\.name)
            let active = g.bins.filter { inv.commands[$0.name] == $0.path }.map(\.name)
            let shadowed = g.bins.filter { inv.commands[$0.name] != $0.path }
            let shownBins = names.prefix(8).joined(separator: "、") + (names.count > 8 ? " 等 \(names.count) 个" : "")
            var detail = "命令：\(shownBins)"
            if !shadowed.isEmpty {
                let examples = shadowed.prefix(3).map { "\($0.name) 实际用的是 \(abbreviate(inv.commands[$0.name] ?? "?", home: ctx.home))" }
                detail += "；被覆盖：" + examples.joined(separator: "，")
            }

            var verdict: Verdict
            var reason: String
            var last: Date?
            var path = g.bins[0].path
            var display = names.count == 1 ? names[0] : "\(names[0]) 等"
            var suggestion: String?

            switch g.origin {
            case .app(let appPath):
                let app = inv.apps.first { $0.path == appPath }
                display = (appPath as NSString).lastPathComponent + " 附带的命令"
                (verdict, reason) = (.keep, "随应用 \(app?.name ?? appPath) 安装，跟着应用走")
                last = hist.lastUse(of: names)?.last
                items.append(Item(section: .cli, name: display, path: appPath, size: 0, lastUsed: last, lastUsedSource: "命令历史",
                                  owner: app?.name, detail: detail, verdict: verdict, reason: reason))
                continue
            case .package(let d, let root):
                display = d
                path = root
                suggestion = "确认不用后删除 \(root) 和这些命令在 \(abbreviate((g.bins[0].path as NSString).deletingLastPathComponent, home: ctx.home)) 里的链接"
            default:
                suggestion = "确认不用后 rm '\(path)'"
            }

            if active.isEmpty {
                (verdict, reason) = (.clean, "全部被 PATH 里更靠前的同名命令覆盖，这里的版本永远不会被执行")
                last = nil
            } else {
                let r = commandVerdict(active)
                (verdict, reason, last) = r
                if !shadowed.isEmpty { reason += "；另有 \(shadowed.count) 个命令被同名命令覆盖" }
            }
            items.append(Item(section: .cli, name: display, path: path, lastUsed: last, lastUsedSource: "命令历史", detail: detail,
                              verdict: verdict, reason: reason, suggestion: verdict == .keep ? nil : suggestion))
        }

        // Never-used standalone programs pile up (e.g. `go install`ed examples); one row per folder.
        fillSizes(&items)
        let neverUsed = items.filter { $0.verdict == .review && $0.lastUsed == nil && groups["file:" + ($0.path ?? "")] != nil }
        if neverUsed.count > 1 {
            let byDir = Dictionary(grouping: neverUsed) { (($0.path ?? "") as NSString).deletingLastPathComponent }
            let folded = Set(neverUsed.compactMap(\.path))
            items.removeAll { folded.contains($0.path ?? "") && $0.verdict == .review && $0.lastUsed == nil }
            for (dir, list) in byDir.sorted(by: { $0.key < $1.key }) {
                items.append(Item(section: .cli, name: "\(abbreviate(dir, home: ctx.home)) 里 \(list.count) 个从没用过的程序", path: dir,
                                  size: list.compactMap(\.size).reduce(0, +),
                                  detail: list.sorted { ($0.size ?? 0) > ($1.size ?? 0) }.map(\.name).joined(separator: "、"),
                                  verdict: .review, reason: "命令历史里一次都没出现过（被脚本或其他程序调用的不会留记录）",
                                  suggestion: "逐个确认后 rm"))
            }
        }

        for missing in inv.missingPathDirs {
            let source = pathDefinition(of: missing)
            items.append(Item(section: .cli, name: "PATH 里不存在的目录 \(abbreviate(missing, home: ctx.home))", path: missing, size: 0,
                              detail: "定义在 \(source ?? "未找到（可能来自 /etc/paths.d 或其他脚本）")", verdict: .clean,
                              reason: "目录不存在，每次查找命令都白白多找一次；常见于换了用户名或卸载了工具",
                              suggestion: source.map { "删掉 \($0) 这一行" } ?? nil))
        }
        fillSizes(&items)
        return items
    }

    private func pathDefinition(of dir: String) -> String? {
        let variants = [dir, dir.replacingOccurrences(of: ctx.home, with: "$HOME"), dir.replacingOccurrences(of: ctx.home, with: "~")]
        for rc in [".zshrc", ".zprofile", ".zshenv", ".bash_profile", ".bashrc", ".profile"] {
            guard let text = readText(ctx.path(rc)) else { continue }
            for (n, line) in text.components(separatedBy: "\n").enumerated() where variants.contains(where: line.contains) {
                return "~/\(rc) 第 \(n + 1) 行"
            }
        }
        return nil
    }

    private func legacyBrew(activePrefix: String) -> Item? {
        let root = legacyBrewPrefix
        guard activePrefix != root, exists(root + "/Homebrew"), isDirectory(root + "/Cellar") else { return nil }
        let formulae = children(root + "/Cellar")
        var stillUsed = [String]()
        var newest: Date?
        for f in formulae {
            let bins = children("\(root)/opt/\(f)/bin").filter { inv.commands[$0] == "\(root)/bin/\($0)" }
            if let use = hist.lastUse(of: bins) {
                newest = max(newest ?? use.last, use.last)
                if !ctx.isStale(use.last) { stillUsed.append(f) }
            }
        }
        let sizes = diskUsage([root + "/Cellar", root + "/Homebrew", root + "/Caskroom"])
        let usedText = stillUsed.isEmpty ? "没有命令还在被实际使用" : "仍在被实际使用的：\(stillUsed.joined(separator: "、"))（卸载前先用新 Homebrew 重装）"
        return Item(section: .brew, name: "旧的 Intel 版 Homebrew（\(root)）", path: root + "/Homebrew", size: sizes.values.reduce(0, +),
                    lastUsed: newest, lastUsedSource: "命令历史",
                    detail: "共 \(formulae.count) 个软件包，Intel 架构，靠 Rosetta 转译运行，通常是从旧 Intel Mac 迁移过来的。\(usedText)",
                    verdict: stillUsed.isEmpty ? .clean : .review,
                    reason: "你现在用的是 \(activePrefix) 下的 Apple 芯片版 Homebrew，两套并存容易混乱",
                    suggestion: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\" -- --path=\(root)")
    }

    // MARK: Development environments

    func devEnv() -> [Item] {
        var items = node() + ruby() + python() + java() + golang()
        fillSizes(&items)
        return items
    }

    private func node() -> [Item] {
        let nvm = ctx.path(".nvm")
        let root = nvm + "/versions/node"
        let versions = children(root).filter { $0.hasPrefix("v") }.sorted(by: compareVersions)
        let activeNode = inv.commands["node"].map(resolvedPath)
        var items = [Item]()
        if exists("/usr/local/n") {
            let inUse = activeNode?.hasPrefix("/usr/local/") ?? false
            items.append(Item(section: .devenv, name: "n 下载的 Node 版本（/usr/local/n）", path: "/usr/local/n",
                              detail: "另一个 Node 版本管理器 n 的缓存：\(children("/usr/local/n/versions/node").joined(separator: "、"))",
                              verdict: inUse ? .keep : .clean,
                              reason: inUse ? "当前的 node 来自 n" : "你现在用 nvm 管理 Node，n 留下的这些版本用不到了",
                              suggestion: inUse ? nil : "sudo rm -rf /usr/local/n"))
        }
        guard !versions.isEmpty else { return items }
        let alias = readText(nvm + "/alias/default") ?? "node"
        let numeric = alias.hasPrefix("v") ? String(alias.dropFirst()) : alias
        let defaultVersion = versions.last { $0 == "v" + numeric || $0.hasPrefix("v" + numeric + ".") } ?? versions.last!

        for v in versions {
            let dir = "\(root)/\(v)"
            let isDefault = v == defaultVersion || (activeNode?.hasPrefix(dir + "/") ?? false)
            let globals = npmGlobals(dir + "/lib/node_modules")
            items.append(Item(section: .devenv, name: "Node.js \(v)", path: dir,
                              detail: "nvm 安装" + (globals.isEmpty ? "" : "；全局包：\(globals.map(\.name).joined(separator: "、"))"),
                              verdict: isDefault ? .keep : .review,
                              reason: isDefault ? "nvm 默认版本（alias default = \(alias)）" : "不是默认版本；没有项目用 .nvmrc 指定它就可以卸载",
                              suggestion: isDefault ? nil : "nvm uninstall \(v)"))
            for pkg in globals {
                let (verdict, reason, last) = commandVerdict(pkg.bins)
                items.append(Item(section: .devenv, name: "npm 全局包 \(pkg.name)（Node \(v)）", path: pkg.path, lastUsed: last,
                                  lastUsedSource: "命令历史",
                                  detail: pkg.bins.isEmpty ? "全局安装的 npm 包" : "提供命令：\(pkg.bins.joined(separator: "、"))",
                                  verdict: verdict, reason: reason,
                                  suggestion: verdict == .keep ? nil : "nvm use \(v) && npm uninstall -g \(pkg.name)"))
            }
        }
        return items
    }

    private func npmGlobals(_ modules: String) -> [(name: String, path: String, bins: [String])] {
        var result = [(name: String, path: String, bins: [String])]()
        var names = [String]()
        for entry in children(modules) where !entry.hasPrefix(".") {
            if entry.hasPrefix("@") {
                names += children(modules + "/" + entry).map { "\(entry)/\($0)" }
            } else {
                names.append(entry)
            }
        }
        for name in names where !["npm", "corepack"].contains(name) {
            let path = modules + "/" + name
            var bins = [String]()
            if let data = fm.contents(atPath: path + "/package.json"),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                if let dict = json["bin"] as? [String: Any] { bins = dict.keys.sorted() }
                else if json["bin"] is String { bins = [(name as NSString).lastPathComponent] }
            }
            result.append((name, path, bins))
        }
        return result
    }

    private func ruby() -> [Item] {
        let root = ctx.path(".rbenv/versions")
        let versions = children(root).sorted(by: compareVersions)
        guard !versions.isEmpty else { return [] }
        let global = readText(ctx.path(".rbenv/version")) ?? "system"
        return versions.map { v in
            let isDefault = v == global
            return Item(section: .devenv, name: "Ruby \(v)", path: "\(root)/\(v)", detail: "rbenv 安装",
                        verdict: isDefault ? .keep : .review,
                        reason: isDefault ? "rbenv 全局默认版本" : "不是 rbenv 默认版本（默认是 \(global)）",
                        suggestion: isDefault ? nil : "rbenv uninstall \(v)")
        }
    }

    private func python() -> [Item] {
        let active = inv.commands["python3"].map(resolvedPath) ?? ""
        var items = [Item]()
        let framework = "/Library/Frameworks/Python.framework/Versions"
        for v in children(framework) where v != "Current" {
            let dir = "\(framework)/\(v)"
            let isDefault = active.hasPrefix(dir + "/")
            let use = hist.lastUse(of: ["python\(v)", "pip\(v)"] + (isDefault ? ["python3", "pip3", "python", "pip"] : []))
            items.append(Item(section: .devenv, name: "Python \(v)（python.org 安装包）", path: dir, lastUsed: use?.last,
                              lastUsedSource: "命令历史", detail: "安装在 /Library/Frameworks，另有 /Applications/Python \(v)",
                              verdict: isDefault && !ctx.isStale(use?.last) ? .keep : .review,
                              reason: isDefault ? "当前默认的 python3" + (ctx.isStale(use?.last) ? "，但很久没用" : "") : "不是当前默认的 python3",
                              suggestion: isDefault ? nil : "sudo rm -rf '\(dir)' '/Applications/Python \(v)'"))
        }
        let pyenv = ctx.path(".pyenv/versions")
        let pyGlobal = readText(ctx.path(".pyenv/version")) ?? ""
        for v in children(pyenv) {
            let isDefault = pyGlobal.lines.contains(v)
            items.append(Item(section: .devenv, name: "Python \(v)（pyenv）", path: "\(pyenv)/\(v)", detail: "pyenv 安装",
                              verdict: isDefault ? .keep : .review, reason: isDefault ? "pyenv 默认版本" : "不是 pyenv 默认版本",
                              suggestion: isDefault ? nil : "pyenv uninstall \(v)"))
        }
        return items
    }

    private func java() -> [Item] {
        let root = "/Library/Java/JavaVirtualMachines"
        let jdks = children(root).filter { $0.hasSuffix(".jdk") }
        guard !jdks.isEmpty else { return [] }
        let home = run("/usr/libexec/java_home", []).out.trimmed
        let use = hist.lastUse(of: ["java", "javac", "mvn", "gradle"])
        return jdks.map { jdk in
            let dir = "\(root)/\(jdk)"
            let isDefault = home.hasPrefix(dir)
            return Item(section: .devenv, name: "JDK \(jdk)", path: dir, lastUsed: use?.last, lastUsedSource: "命令历史（java/javac/mvn/gradle）",
                        detail: "Java 开发工具包", verdict: isDefault && !ctx.isStale(use?.last) ? .keep : .review,
                        reason: isDefault ? "当前默认 JDK" + (ctx.isStale(use?.last) ? "，但 java/javac/mvn/gradle 超过 \(ctx.staleDays) 天没用" : "")
                                          : "不是当前默认 JDK",
                        suggestion: isDefault ? nil : "sudo rm -rf '\(dir)'")
        }
    }

    private func golang() -> [Item] {
        let root = "/usr/local/go"
        guard exists(root) else { return [] }
        let version = readText(root + "/VERSION")?.lines.first ?? "Go"
        let (verdict, reason, last) = commandVerdict(["go"])
        return [Item(section: .devenv, name: version, path: root, lastUsed: last, lastUsedSource: "命令历史",
                     detail: "官方安装包装在 /usr/local/go", verdict: verdict, reason: reason,
                     suggestion: verdict == .keep ? nil : "sudo rm -rf /usr/local/go")]
    }

    // MARK: Dotfiles

    func dotfiles() -> [Item] {
        var items = [Item]()
        for name in children(ctx.home) where name.hasPrefix(".") && ![".Trash", ".DS_Store"].contains(name) {
            let full = ctx.path(name)
            let touched = newestModification(full)
            guard let info = lookupDotfile(name) else {
                let sample = children(full).prefix(6).joined(separator: "、")
                items.append(Item(section: .dotfiles, name: name, path: full, lastUsed: touched, lastUsedSource: "文件修改时间",
                                  detail: isDirectory(full) ? "内容：\(sample.isEmpty ? "空" : sample)" : "单个文件",
                                  verdict: .unknown, reason: "知识库里还没有它，需要人工或 AI 识别"))
                continue
            }
            var verdict: Verdict
            var reason: String
            var owner: String? = info.owner
            switch info.kind {
            case .system: (verdict, reason) = (.keep, "macOS 自带")
            case .secret: (verdict, reason) = (.keep, "包含密钥或凭据，不要删")
            case .config: (verdict, reason) = (.keep, "配置，删了相关工具会恢复成默认设置")
            case .toolchain: (verdict, reason) = (.keep, "开发环境，逐个版本的判断见「开发环境」")
            case .itemizedElsewhere: (verdict, reason) = (.keep, "里面的内容在「缓存」一节逐项列出，这里不重复计算")
            case .history: (verdict, reason) = (.clean, "只是历史记录，删了不影响使用")
            case .cache: (verdict, reason) = (.clean, "缓存，会自动重新生成")
            case .data:
                let checks = !info.apps.isEmpty || !info.commands.isEmpty
                let found = inv.findApp(info.apps)?.name ?? inv.findCommand(info.commands).map { "命令 \(($0 as NSString).lastPathComponent)" }
                if let found {
                    owner = found
                    if ctx.isStale(touched) {
                        (verdict, reason) = (.review, "所属软件（\(found)）还在，但这里\(staleText(touched))没更新")
                    } else {
                        (verdict, reason) = (.keep, "所属软件（\(found)）还在用")
                    }
                } else if checks {
                    if ctx.isStale(touched) {
                        (verdict, reason) = (.clean, "没找到 \(info.owner)，且\(staleText(touched))没更新，是卸载残留")
                    } else {
                        (verdict, reason) = (.review, "没找到 \(info.owner)，但最近有写入，可能装在别处")
                    }
                } else {
                    (verdict, reason) = (ctx.isStale(touched) ? .review : .keep,
                                         "无法自动确认是否还在用" + (ctx.isStale(touched) ? "，\(staleText(touched))没更新" : "，最近有写入"))
                }
            }
            items.append(Item(section: .dotfiles, name: name, path: full, lastUsed: touched, lastUsedSource: "文件修改时间", owner: owner,
                              detail: (info.guess ? "（推测）" : "") + info.what, verdict: verdict, reason: reason,
                              suggestion: info.suggestion ?? (verdict == .clean ? "移到废纸篓" : nil)))
        }
        fillSizes(&items)
        return items
    }

    // MARK: Leftovers in ~/Library

    func leftovers() -> [Item] {
        struct Candidate {
            var display: String
            var isBundleID: Bool
            var aliasOwner: String?
            var places: [(label: String, path: String)] = []
        }
        let lib = ctx.path("Library")
        // Other apps' containers are TCC-protected; only their names are read.
        let protected: Set<String> = ["Containers", "Group Containers"]
        let sources = ["Application Support", "Caches", "Preferences", "Containers", "Group Containers", "Logs",
                       "Saved Application State", "HTTPStorages", "WebKit"]
        var candidates = [String: Candidate]()
        var order = [String]()

        for label in sources {
            let dir = "\(lib)/\(label)"
            for entry in children(dir) where !entry.hasPrefix(".") {
                var id = entry
                switch label {
                case "Preferences":
                    guard entry.hasSuffix(".plist") else { continue }
                    id = String(entry.dropLast(6))
                case "Saved Application State":
                    id = id.replacingOccurrences(of: ".savedState", with: "")
                default: break
                }
                if id.hasPrefix("group.") { id = String(id.dropFirst(6)) }
                if let r = id.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) { id = String(id[r.upperBound...]) }
                let lower = id.lowercased()
                if lower.contains("com.apple") || lower.hasPrefix("apple") || appleLibraryNames.contains(id)
                    || lower.hasPrefix("systemgroup.") || lower == "loginwindow" || lower.hasPrefix("pbs")
                    || id.range(of: #"^[a-z]+d$"#, options: .regularExpression) != nil { continue }
                if label == "Caches", toolCaches[entry] != nil { continue }
                let isBundle = id.split(separator: ".").count >= 3 && !id.contains(" ")
                let alias = libraryAliases[lower]
                if let alias {
                    let checks = !alias.apps.isEmpty || !alias.commands.isEmpty
                    if checks, inv.findApp(alias.apps) != nil || inv.findCommand(alias.commands) != nil { continue }
                } else {
                    let owned = isBundle ? (inv.owner(ofBundleID: id) ?? inv.vendorMatch(ofBundleID: id)) : inv.owner(ofName: id)
                    if owned != nil { continue }
                }
                // An app's extensions and helpers (com.vendor.app.*) collapse into one entry.
                let key = isBundle ? lower.split(separator: ".").prefix(3).joined(separator: ".") : lower
                if candidates[key] == nil {
                    candidates[key] = Candidate(display: isBundle ? id.split(separator: ".").prefix(3).joined(separator: ".") : id,
                                                isBundleID: isBundle, aliasOwner: alias?.owner)
                    order.append(key)
                }
                candidates[key]!.places.append((label, "\(dir)/\(entry)"))
            }
        }
        for key in order.sorted(by: { $0.count < $1.count }) {
            guard candidates[key] != nil else { continue }
            for other in order where other != key && other.hasPrefix(key + ".") {
                if let c = candidates.removeValue(forKey: other) { candidates[key]!.places += c.places }
            }
        }
        // Plain names like "DingTalkMac" join the bundle-ID entry they belong to (com.alibaba.DingTalkMac).
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let bundleKeys = order.filter { candidates[$0]?.isBundleID == true }
        for key in order where candidates[key]?.isBundleID == false {
            let n = norm(candidates[key]!.display)
            guard n.count >= 4 else { continue }
            let target = bundleKeys.first { bk in
                bk.split(separator: ".").dropFirst(2).contains { comp in
                    let c = norm(String(comp))
                    return c.count >= 4 && (c == n || c.hasPrefix(n) || n.hasPrefix(c))
                }
            }
            if let target, let c = candidates.removeValue(forKey: key) {
                candidates[target]!.places += c.places
                if candidates[target]!.aliasOwner == nil { candidates[target]!.aliasOwner = c.aliasOwner }
            }
        }
        order = order.filter { candidates[$0] != nil }

        let sizes = diskUsage(candidates.values.flatMap { $0.places.filter { !protected.contains($0.label) }.map(\.path) })
        let lowRisk: Set<String> = ["Caches", "Logs", "Saved Application State", "HTTPStorages", "WebKit", "Preferences"]
        let disposable: Set<String> = ["Caches", "Logs", "Saved Application State", "HTTPStorages"]
        let items: [Item] = order.compactMap { key in
            let c = candidates[key]!
            let measurable = c.places.filter { !protected.contains($0.label) }
            let size = measurable.compactMap { sizes[$0.path] }.reduce(0, +)
            let touched = c.places.compactMap { protected.contains($0.label) ? modificationDate($0.path) : newestModification($0.path, maxDepth: 1) }.max()
            var seenLabels = Set<String>()
            let labels = c.places.map(\.label).filter { seenLabels.insert($0).inserted }.joined(separator: "、")
                + (c.places.count > seenLabels.count ? "（共 \(c.places.count) 处）" : "")
            let unmeasured = c.places.count > measurable.count ? "（容器类目录需完全磁盘访问权限才能统计大小）" : ""
            let electron = c.places.contains { exists($0.path + "/Code Cache") && exists($0.path + "/Cookies") }
            let knownOwner = c.aliasOwner.map { !$0.hasPrefix("某") && !$0.contains("某个") } ?? false
            let verdict: Verdict
            let reason: String
            if c.places.allSatisfy({ disposable.contains($0.label) }) {
                (verdict, reason) = (.clean, "只有缓存/日志，删除不会丢数据")
            } else if c.isBundleID || knownOwner {
                let who = c.aliasOwner.map { "\($0) 已不在电脑上" } ?? "按 bundle ID 找不到已安装的应用"
                if c.places.allSatisfy({ lowRisk.contains($0.label) }) {
                    (verdict, reason) = (.clean, "\(who)，只剩缓存/日志/偏好设置")
                } else {
                    (verdict, reason) = (.review, "\(who)；里面可能有聊天记录、下载等数据，确认不要了再删")
                }
            } else if ctx.isStale(touched) {
                (verdict, reason) = (.review, "找不到同名的应用或命令，且\(staleText(touched))没更新，很可能是已卸载软件的残留")
            } else {
                (verdict, reason) = (.unknown, "找不到同名的应用或命令，但最近有写入，可能是某个名字对不上的应用在用")
            }
            var detail = "位置：\(labels)\(unmeasured)"
            if let owner = c.aliasOwner { detail = "属于 \(owner)。" + detail }
            if electron { detail += "。看结构是某个 Electron 应用的数据（网页缓存和登录状态）" }
            return Item(section: .leftovers, name: c.display, path: c.places.first?.path, size: size, lastUsed: touched,
                        lastUsedSource: "文件修改时间", owner: c.aliasOwner, detail: detail, verdict: verdict, reason: reason,
                        suggestion: "移到废纸篓：" + c.places.map { abbreviate($0.path, home: ctx.home) }.joined(separator: "；"))
        }

        // Tiny entries are noise one by one; fold each verdict's into a single row.
        let threshold: Int64 = 1024 * 1024
        var result = items.filter { ($0.size ?? 0) >= threshold || $0.verdict == .review || $0.detail.contains("容器类") }
        for verdict in [Verdict.clean, .unknown] {
            let small = items.filter { $0.verdict == verdict && ($0.size ?? 0) < threshold && !$0.detail.contains("容器类") && $0.verdict != .review }
            guard !small.isEmpty else { continue }
            result.append(Item(section: .leftovers, name: "\(small.count) 个很小的条目", size: small.compactMap(\.size).reduce(0, +),
                               detail: small.map(\.name).joined(separator: "、"), verdict: verdict,
                               reason: verdict == .clean ? "都不到 1MB，属于已卸载软件或只有缓存" : "都不到 1MB，暂时认不出是谁的",
                               suggestion: verdict == .clean ? "不占空间，想彻底干净可以逐个删" : nil))
        }
        return result
    }

    // MARK: Launch agents & daemons

    func launchItems() -> [Item] {
        let dirs: [(path: String, kind: String, system: Bool)] = [
            (ctx.path("Library/LaunchAgents"), "当前用户登录后启动", false),
            ("/Library/LaunchAgents", "所有用户登录后启动", true),
            ("/Library/LaunchDaemons", "开机就运行的系统级服务", true),
        ]
        var items = [Item]()
        for dir in dirs {
            for file in children(dir.path) where file.hasSuffix(".plist") {
                let plistPath = "\(dir.path)/\(file)"
                let dict = readPlist(plistPath) ?? [:]
                let label = dict["Label"] as? String ?? String(file.dropLast(6))
                let args = dict["ProgramArguments"] as? [String] ?? []
                var program = dict["Program"] as? String ?? args.first
                if let p = program, p.hasPrefix("./"), let wd = dict["WorkingDirectory"] as? String {
                    program = (wd as NSString).appendingPathComponent(String(p.dropFirst(2)))
                }
                // Wrappers like `open -a /path/App.app` or `sh -c ...`: judge by the first absolute path mentioned.
                let checkPath = ([program].compactMap { $0 } + args).first { $0.hasPrefix("/") && !$0.hasPrefix("/bin/") && !$0.hasPrefix("/usr/bin/") }
                let programExists = checkPath.map(exists) ?? true
                var ownerApp: AppInfo?
                if let program = checkPath ?? program, let r = program.range(of: ".app/") {
                    let appPath = String(program[..<r.lowerBound]) + ".app"
                    ownerApp = inv.apps.first { $0.path == appPath }
                }
                var associated = (dict["AssociatedBundleIdentifiers"] as? [String]) ?? []
                if let s = dict["AssociatedBundleIdentifiers"] as? String { associated.append(s) }
                let ownerName = ownerApp?.name
                    ?? ([label] + associated).lazy.compactMap { self.inv.owner(ofBundleID: $0) ?? self.inv.vendorMatch(ofBundleID: $0) }.first
                if ownerApp == nil, let ownerName { ownerApp = inv.apps.first { $0.name == ownerName } }

                let verdict: Verdict
                let reason: String
                if !programExists {
                    (verdict, reason) = (.clean, "要运行的程序（\(abbreviate(checkPath ?? "", home: ctx.home))）已不存在，是卸载残留，每次启动都会白白报错")
                } else if ownerName == nil {
                    (verdict, reason) = (.review, "没找到对应的应用，可能是卸载后留下的帮助程序")
                } else if let app = ownerApp, !app.isApple, ctx.isStale(app.lastUsed) {
                    (verdict, reason) = (.review, "所属应用 \(app.name) \(staleText(app.lastUsed))没打开，但它的后台服务一直在运行")
                } else {
                    (verdict, reason) = (.keep, "所属应用 \(ownerName!) 还在")
                }
                let remove = dir.system
                    ? "sudo launchctl bootout system '\(plistPath)'; sudo rm '\(plistPath)'"
                    : "launchctl bootout gui/$(id -u) '\(plistPath)'; rm '\(plistPath)'"
                items.append(Item(section: .launch, name: label, path: plistPath, size: 0, lastUsed: ownerApp?.lastUsed,
                                  lastUsedSource: ownerApp == nil ? nil : "所属应用的打开时间", owner: ownerName,
                                  detail: "\(dir.kind)；程序：\(program.map { abbreviate($0, home: ctx.home) } ?? "由系统按 bundle 定位")"
                                      + ((dict["Disabled"] as? Bool) == true ? "；已禁用" : ""),
                                  verdict: verdict, reason: reason,
                                  suggestion: verdict == .keep ? nil : remove + (programExists && checkPath != nil && ownerApp == nil ? "；确认后再删除程序 \(checkPath!)" : "")))
            }
        }
        return items
    }

    // MARK: Caches

    func caches() -> [Item] {
        let known: [(path: String, name: String, suggestion: String, verdict: Verdict)] = [
            (".Trash", "废纸篓", "在访达里清倒废纸篓", .clean),
            ("Library/Caches/Homebrew", "Homebrew 下载缓存", "brew cleanup --prune=all", .clean),
            (".npm/_cacache", "npm 下载缓存", "npm cache clean --force", .clean),
            ("Library/Caches/go-build", "Go 编译缓存", "go clean -cache", .clean),
            ("go/pkg/mod", "Go 模块下载缓存", "go clean -modcache", .clean),
            ("Library/Caches/pip", "pip 下载缓存", "pip3 cache purge", .clean),
            ("Library/Caches/Yarn", "Yarn 缓存", "yarn cache clean", .clean),
            ("Library/Caches/CocoaPods", "CocoaPods 缓存", "pod cache clean --all", .clean),
            ("Library/Developer/Xcode/DerivedData", "Xcode 编译中间产物", "直接删除，下次编译重新生成", .clean),
            ("Library/Developer/Xcode/iOS DeviceSupport", "Xcode 真机调试符号", "删掉不再调试的 iOS 版本", .clean),
            ("Library/Developer/CoreSimulator/Caches", "iOS 模拟器缓存", "xcrun simctl delete unavailable", .clean),
            (".gradle/caches", "Gradle 依赖缓存", "直接删除，下次构建重新下载", .clean),
            (".m2/repository", "Maven 本地仓库", "删除后下次构建要重新下载全部依赖", .review),
        ]
        var items = known.compactMap { k -> Item? in
            let full = ctx.path(k.path)
            guard exists(full) else { return nil }
            return Item(section: .caches, name: k.name, path: full, detail: abbreviate(full, home: ctx.home), verdict: k.verdict,
                        reason: k.verdict == .clean ? "可安全清理，需要时会重新生成或下载" : "能清，但重建很慢", suggestion: k.suggestion)
        }

        let xdgOwners = ["uv": "uv（Python 包管理器）", "codex-runtimes": "Codex", "github-copilot": "GitHub Copilot", "prisma": "Prisma",
                         "rubocop_cache": "RuboCop", "node": "Node 工具（corepack 等）", "pip": "pip", "huggingface": "Hugging Face 模型",
                         "puppeteer": "Puppeteer 浏览器", "ms-playwright": "Playwright 浏览器"]
        for child in children(ctx.path(".cache")) where !child.hasPrefix(".") {
            let heavy = ["huggingface", "ms-playwright", "puppeteer"].contains(child)
            items.append(Item(section: .caches, name: "~/.cache/\(child)", path: ctx.path(".cache/\(child)"), owner: xdgOwners[child],
                              detail: xdgOwners[child].map { "\($0) 的缓存" } ?? "命令行工具缓存", verdict: heavy ? .review : .clean,
                              reason: heavy ? "能清，但重新下载很慢" : "缓存，会自动重新生成", suggestion: "移到废纸篓"))
        }

        let covered = Set(known.map { ctx.path($0.path) })
        for child in children(ctx.path("Library/Caches")) where !child.hasPrefix(".") && !child.lowercased().contains("com.apple") {
            let full = ctx.path("Library/Caches/\(child)")
            guard !covered.contains(full), !appleLibraryNames.contains(child) else { continue }
            if let desc = toolCaches[child] {
                items.append(Item(section: .caches, name: child, path: full, detail: desc, verdict: .clean,
                                  reason: "开发工具缓存，需要时会重新生成或下载", suggestion: "移到废纸篓"))
                continue
            }
            let isBundle = child.split(separator: ".").count >= 3
            guard let owner = isBundle ? (inv.owner(ofBundleID: child) ?? inv.vendorMatch(ofBundleID: child)) : inv.owner(ofName: child) else { continue }
            items.append(Item(section: .caches, name: child, path: full, owner: owner, detail: "\(owner) 的缓存", verdict: .clean,
                              reason: "应用缓存，删了应用会重新生成（先退出该应用）", suggestion: "退出 \(owner) 后移到废纸篓"))
        }
        fillSizes(&items)
        return items.filter { ($0.size ?? 0) >= 20 * 1024 * 1024 || $0.name == "废纸篓" }
    }
}
