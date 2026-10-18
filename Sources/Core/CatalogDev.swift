import Foundation

struct Toolchain {
    let id: String
    let title: String
    let summary: String
    /// Folder names, dotfile owners and commands that belong to this toolchain (case-insensitive).
    let names: [String]
}

let toolchains: [Toolchain] = [
    Toolchain(id: "homebrew", title: "Homebrew", summary: "命令行软件包管理器，以及用它装的软件",
              names: ["homebrew", "brew"]),
    Toolchain(id: "node", title: "Node.js 与前端工具", summary: "JavaScript 运行环境，npm / Yarn / pnpm 等包管理器和相关工具",
              names: ["nvm", ".nvm", ".npm", ".npmrc", ".yarnrc", "npm", "node", "yarn", "pnpm", "corepack", "node-gyp", "typescript",
                      "prisma", "prisma-nodejs", "checkpoint-nodejs", "js-v8flags", "ms-playwright", "puppeteer", "node 工具",
                      "node 工具（corepack 等）", "node.js", "deno", "bun"]),
    Toolchain(id: "go", title: "Go", summary: "Go 语言工具链、go install 装的程序、模块和编译缓存",
              names: ["go", "go-build", "goimports", "gopls", "delve", ".dlv", "kratos cli", ".kratos", "kratos", "staticcheck", "fyne"]),
    Toolchain(id: "python", title: "Python", summary: "Python 解释器、pip / uv 等包管理器和缓存",
              names: ["python", "python3", "pip", "pip3", "pyenv", ".pyenv", "uv", "uv（python 包管理器）", "matplotlib", ".matplotlib",
                      "python idle", ".idlerc", "huggingface", "hugging face 模型"]),
    Toolchain(id: "ruby", title: "Ruby", summary: "Ruby 解释器、gem、Bundler 和 CocoaPods",
              names: ["ruby", "rbenv", ".rbenv", "rubygems", ".gem", "bundler（ruby）", ".bundle", "cocoapods", "rubocop_cache", "gem"]),
    Toolchain(id: "java", title: "Java", summary: "JDK 以及 Maven、Gradle 的依赖缓存",
              names: ["java", "jna", ".m2", ".gradle", "gradle", "maven", "javac"]),
    Toolchain(id: "rust", title: "Rust", summary: "Rust 工具链 rustup / cargo",
              names: ["rust", ".cargo", ".rustup", "cargo", "rustc"]),
    Toolchain(id: "swift", title: "Swift 与 LLDB", summary: "Swift 包管理器和调试器的配置与缓存",
              names: ["swift", ".swiftpm", "lldb", ".lldb", "org.swift.swiftpm"]),
    Toolchain(id: "android", title: "Android 开发工具", summary: "adb、模拟器和 Android Studio 的配置",
              names: ["android sdk / android studio", ".android", "adb"]),
]

private let toolCommands: [String: [String]] = [
    "homebrew": ["brew"], "node": ["node", "npm", "npx", "pnpm", "yarn", "nvm"], "go": ["go"],
    "python": ["python", "python3", "pip", "pip3", "uv"], "ruby": ["ruby", "gem", "bundle", "rbenv", "pod"],
    "java": ["java", "javac", "mvn", "gradle"], "rust": ["cargo", "rustc", "rustup"], "swift": ["swift", "swiftc"],
    "android": ["adb", "emulator"],
]

extension CatalogBuilder {
    func toolchain(named name: String) -> String? {
        let lower = name.lowercased()
        return toolchains.first { $0.names.contains(lower) }?.id
    }

    func toolShelf(_ id: String) -> String {
        let t = toolchains.first { $0.id == id }!
        return shelf("tool:" + id, .dev, t.title, t.summary)
    }

    // MARK: Development environments

    func addDevEnvironments() {
        let s = Scanners(ctx: ctx)
        addHomebrew(s.brew())

        for item in s.devEnv() {
            guard let path = item.path else { continue }
            let tool: String
            switch item.name {
            case let n where n.hasPrefix("npm 全局包"): continue
            case let n where n.hasPrefix("Node.js") || n.hasPrefix("n 下载"): tool = "node"
            case let n where n.hasPrefix("Ruby"): tool = "ruby"
            case let n where n.hasPrefix("Python"): tool = "python"
            case let n where n.hasPrefix("JDK"): tool = "java"
            case let n where n.hasPrefix("go"): tool = "go"
            default: continue
            }
            var b = book(path, .toolchain, note: "\(item.name)：\(item.reason)" + (item.detail.isEmpty ? "" : "；\(item.detail)"))
            // Only the active version gets the toolchain's command history; the others are simply not in use.
            if item.reason.hasPrefix("不是") || item.reason.contains("用不到了") {
                b.idle = true
            } else {
                b.lastUsed = item.lastUsed ?? ctx.history.lastUse(of: toolCommands[tool] ?? [])?.last
            }
            add(b, to: toolShelf(tool))
        }
        for (tool, cmds) in toolCommands {
            update("tool:" + tool) { $0.lastUsed = ctx.history.lastUse(of: cmds)?.last; $0.lastUsedSource = "命令历史" }
        }

        let goRoot = home + "/go"
        if isDirectory(goRoot) {
            let go = toolShelf("go")
            add(book(goRoot, .toolchain, note: "GOPATH：go install 装的程序（bin）、下载的模块（pkg）、旧式源码（src）"), to: go)
            for sub in children(goRoot) where isDirectory(goRoot + "/" + sub) {
                add(book(goRoot + "/" + sub, sub == "pkg" ? .cache : .toolchain), to: go)
            }
        }
        for (rel, tool, note) in [(".gradle", "java", "Gradle 的依赖缓存和守护进程数据"), (".m2", "java", "Maven 本地仓库")] {
            let p = home + "/" + rel
            if exists(p) { add(book(p, .cache, note: note), to: toolShelf(tool)) }
        }
    }

    private func addHomebrew(_ items: [Item]) {
        guard let brew = inv.findCommand(["brew"]) else { return }
        let prefix = ((resolvedPath(brew) as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        let byName = Dictionary(items.map { (($0.name as NSString).lastPathComponent.replacingOccurrences(of: "（cask）", with: ""), $0) },
                                uniquingKeysWith: { a, _ in a })
        let id = toolShelf("homebrew")
        var core = book(prefix + "/Library", .toolchain, note: "Homebrew 自身（\(prefix)）")
        core.lastUsed = ctx.history.lastUse(of: ["brew"])?.last
        add(core, to: id)
        let leaves = Set(items.filter { !$0.name.hasSuffix("（cask）") }.map(\.name))
        for f in children(prefix + "/Cellar") {
            let role = leaves.contains(f) ? "主动安装" : "被其他软件依赖而自动安装"
            var b = book(prefix + "/Cellar/" + f, .toolchain, note: "\(f)：\(role)" + (byName[f].map { "；\($0.reason)；\($0.detail)" } ?? ""))
            b.lastUsed = byName[f]?.lastUsed
            add(b, to: id)
        }
        for c in children(prefix + "/Caskroom") {
            var b = book(prefix + "/Caskroom/" + c, .program, note: "用 brew 装的图形应用 \(c)" + (byName[c].map { "；" + $0.reason } ?? ""))
            b.lastUsed = byName[c]?.lastUsed
            add(b, to: id)
        }
    }

    // MARK: Terminal: shell config, commands, keys, history

    private var shellOwners: Set<String> { ["zsh", "bash", "shell", "oh-my-zsh", "终端"] }

    func addTerminal() {
        let shellID = shelf("term:shell", .terminal, "Shell 配置", "打开终端时执行的配置文件和框架（zsh、bash、oh-my-zsh）")
        let secrets = shelf("term:secrets", .terminal, "密钥与凭据", "SSH / GPG 密钥、登录令牌，丢了很麻烦，泄露更麻烦")
        let historyID = shelf("term:history", .terminal, "历史记录", "各种命令行工具的输入历史，删了只是丢历史")
        let configs = shelf("term:configs", .terminal, "其他工具的配置", "Git、Vim 等命令行工具的配置")

        let zshrc = readText(home + "/.zshrc") ?? ""
        let s = Scanners(ctx: ctx)
        for item in s.otherCLI() {
            guard let path = item.path else { continue }
            if item.name.hasPrefix("PATH 里不存在的目录") {
                update(shellID) { $0.flags.append("\(item.name)（\(item.detail)）") }
                continue
            }
            var b = book(path, .command, note: "\(item.name)：\(item.reason)；\(item.detail)", size: item.size)
            b.lastUsed = item.lastUsed
            b.idle = item.reason.hasPrefix("全部被 PATH") || item.reason.hasPrefix("链接指向的程序已不存在")
            if path.hasPrefix(home + "/go/") || path == home + "/go/bin" {
                add(b, to: toolShelf("go"))
            } else {
                add(b, to: shelf("term:cli", .terminal, "命令行工具", "不是 Homebrew 装的命令：手动下载、安装包附带、npm 等"))
            }
        }

        for name in children(home) where name.hasPrefix(".") && ![".Trash", ".DS_Store"].contains(name) {
            let path = home + "/" + name
            guard let info = lookupDotfile(name) else {
                place(book(path, isDirectory(path) ? .folder : .file, note: "知识库里还没有它"), id: String(name.dropFirst()), entry: String(name.dropFirst()))
                continue
            }
            let note = (info.guess ? "（推测）" : "") + info.what
            let tool = toolchain(named: name) ?? toolchain(named: info.owner)
            switch info.kind {
            case .system:
                add(book(path, .config, note: note), to: shelf("apple:data", .system, "系统和自带应用的数据", "照片、信息、邮件、iCloud 等苹果自带功能的数据"))
            case .secret:
                add(book(path, .secret, note: note), to: tool.map(toolShelf) ?? secrets)
            case .history:
                add(book(path, .history, note: note), to: historyID)
            case .config:
                if shellOwners.contains(info.owner) || name.hasPrefix(".zsh") {
                    var b = book(path, .config, note: note)
                    // Loaded by every new zsh: the shell history's last write is its last use.
                    if name.hasPrefix(".zsh") || zshrc.contains(name) { b.lastUsed = modificationDate(home + "/.zsh_history") }
                    add(b, to: shellID)
                } else if let tool {
                    add(book(path, .config, note: note), to: toolShelf(tool))
                } else {
                    add(book(path, .config, note: note), to: configs)
                }
            case .cache:
                if shellOwners.contains(info.owner) || name.hasPrefix(".zcompdump") {
                    add(book(path, .cache, note: note), to: shellID)
                } else {
                    place(book(path, .cache, note: note), id: info.owner, entry: tool ?? info.owner)
                }
            case .toolchain:
                var b = book(path, .toolchain, note: note)
                b.lastUsed = tool.flatMap { toolCommands[$0] }.flatMap { ctx.history.lastUse(of: $0)?.last }
                add(b, to: tool.map(toolShelf) ?? shelf("tool:other", .dev, "其他工具链", "其他语言的版本管理器和工具链"))
            case .itemizedElsewhere:
                if name == ".cache" {
                    for child in children(path) where !child.hasPrefix(".") {
                        place(book(path + "/" + child, .cache, note: "~/.cache 里的缓存"), id: child, entry: child)
                    }
                } else {
                    add(book(path, .cache, note: note), to: tool.map(toolShelf) ?? configs)
                }
            case .data:
                let b = book(path, .userData, note: note)
                if let app = inv.findApp(info.apps), let real = inv.apps.first(where: { $0.path == app.path }) {
                    add(b, to: appShelfID(real))
                } else if let tool {
                    add(b, to: toolShelf(tool))
                } else if let cmd = info.commands.first(where: { inv.commands[$0] != nil }) {
                    add(b, to: shelf("cmd:" + cmd, .terminal, "\(cmd)（命令行工具）", "命令 \(cmd) 的数据和配置"))
                } else if info.apps.isEmpty && info.commands.isEmpty {
                    add(b, to: configs)
                } else {
                    orphanPool.append(OrphanEntry(id: name, isBundleID: false, alias: info.owner, note: "没找到 \(info.owner)", book: b))
                }
            }
        }
    }
}
