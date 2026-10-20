import Foundation

struct Toolchain {
    let id: String
    let title: String
    let summary: String
    /// Folder names, dotfile owners and commands that belong to this toolchain (case-insensitive).
    let names: [String]
}

let toolchains: [Toolchain] = [
    Toolchain(id: "homebrew", title: "Homebrew", summary: L("The command-line package manager, and what it installed"),
              names: ["homebrew", "brew"]),
    Toolchain(id: "node", title: L("Node.js & front-end tools"), summary: L("The JavaScript runtime, npm / Yarn / pnpm and related tools"),
              names: ["nvm", ".nvm", ".npm", ".npmrc", ".yarnrc", "npm", "node", "yarn", "pnpm", "corepack", "node-gyp", "typescript",
                      "prisma", "prisma-nodejs", "checkpoint-nodejs", "js-v8flags", "ms-playwright", "puppeteer", "node tools",
                      "node.js", "deno", "bun"]),
    Toolchain(id: "go", title: "Go", summary: L("The Go toolchain, programs from go install, modules and build caches"),
              names: ["go", "go-build", "goimports", "gopls", "delve", ".dlv", "kratos cli", ".kratos", "kratos", "staticcheck", "fyne"]),
    Toolchain(id: "python", title: "Python", summary: L("Python interpreters, pip / uv and their caches"),
              names: ["python", "python3", "pip", "pip3", "pyenv", ".pyenv", "uv", "matplotlib", ".matplotlib",
                      "python idle", ".idlerc", "huggingface"]),
    Toolchain(id: "ruby", title: "Ruby", summary: L("Ruby interpreters, gems, Bundler and CocoaPods"),
              names: ["ruby", "rbenv", ".rbenv", "rubygems", ".gem", "bundler (ruby)", ".bundle", "cocoapods", "rubocop_cache", "gem"]),
    Toolchain(id: "java", title: "Java", summary: L("JDKs and the Maven and Gradle dependency caches"),
              names: ["java", "jna", ".m2", ".gradle", "gradle", "maven", "javac"]),
    Toolchain(id: "rust", title: "Rust", summary: L("The Rust toolchain: rustup and cargo"),
              names: ["rust", ".cargo", ".rustup", "cargo", "rustc"]),
    Toolchain(id: "swift", title: L("Swift & LLDB"), summary: L("Settings and caches of the Swift package manager and debugger"),
              names: ["swift", ".swiftpm", "lldb", ".lldb", "org.swift.swiftpm"]),
    Toolchain(id: "android", title: L("Android tools"), summary: L("Settings of adb, the emulator and Android Studio"),
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
            guard let path = item.path, let tool = item.tool else { continue }
            var b = book(path, .toolchain, note: L("\(item.name): \(item.reason)") + (item.detail.isEmpty ? "" : L("; \(item.detail)")))
            // Only the active version gets the toolchain's command history; the others are simply not in use.
            if item.idle {
                b.idle = true
            } else {
                b.lastUsed = item.lastUsed ?? ctx.history.lastUse(of: toolCommands[tool] ?? [])?.last
            }
            add(b, to: toolShelf(tool))
        }
        for (tool, cmds) in toolCommands {
            update("tool:" + tool) { $0.lastUsed = ctx.history.lastUse(of: cmds)?.last; $0.lastUsedSource = L("Command history") }
        }

        let goRoot = home + "/go"
        if isDirectory(goRoot) {
            let go = toolShelf("go")
            add(book(goRoot, .toolchain, note: L("GOPATH: programs from go install (bin), downloaded modules (pkg), old-style sources (src)")), to: go)
            for sub in children(goRoot) where isDirectory(goRoot + "/" + sub) {
                add(book(goRoot + "/" + sub, sub == "pkg" ? .cache : .toolchain), to: go)
            }
        }
        for (rel, tool, note) in [(".gradle", "java", L("Gradle dependency cache and daemon data")), (".m2", "java", L("Maven local repository"))] {
            let p = home + "/" + rel
            if exists(p) { add(book(p, .cache, note: note), to: toolShelf(tool)) }
        }
    }

    private func addHomebrew(_ items: [Item]) {
        guard let brew = inv.findCommand(["brew"]) else { return }
        let prefix = ((resolvedPath(brew) as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        let byName = Dictionary(items.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let id = toolShelf("homebrew")
        var core = book(prefix + "/Library", .toolchain, note: L("Homebrew itself (\(prefix))"))
        core.lastUsed = ctx.history.lastUse(of: ["brew"])?.last
        add(core, to: id)
        let leaves = Set(items.filter { !$0.cask && $0.path?.contains("/Cellar/") == true }.map(\.name))
        for f in children(prefix + "/Cellar") {
            let role = leaves.contains(f) ? L("installed on purpose") : L("installed automatically as a dependency")
            var b = book(prefix + "/Cellar/" + f, .toolchain, note: L("\(f): \(role)") + (byName[f].map { L("; \($0.reason); \($0.detail)") } ?? ""))
            b.lastUsed = byName[f]?.lastUsed
            add(b, to: id)
        }
        for c in children(prefix + "/Caskroom") {
            var b = book(prefix + "/Caskroom/" + c, .program, note: L("App \(c), installed with brew") + (byName[c].map { L("; \($0.reason)") } ?? ""))
            b.lastUsed = byName[c]?.lastUsed
            add(b, to: id)
        }
    }

    // MARK: Terminal: shell config, commands, keys, history

    private var shellOwners: Set<String> { ["zsh", "bash", "shell", "oh-my-zsh", "Terminal"] }

    func addTerminal() {
        let shellID = shelf("term:shell", .terminal, L("Shell configuration"), L("Files and frameworks run when a terminal opens (zsh, bash, oh-my-zsh)"))
        let secrets = shelf("term:secrets", .terminal, L("Keys & credentials"), L("SSH / GPG keys and login tokens: a pain to lose, worse to leak"))
        let historyID = shelf("term:history", .terminal, L("Histories"), L("What you typed into command-line tools; deleting only loses the history"))
        let configs = shelf("term:configs", .terminal, L("Other tools' settings"), L("Settings of Git, Vim and other command-line tools"))

        let zshrc = readText(home + "/.zshrc") ?? ""
        let s = Scanners(ctx: ctx)
        for item in s.otherCLI() {
            guard let path = item.path else { continue }
            if item.missingDirectory {
                update(shellID) { $0.flags.append(L("\(item.name) (\(item.detail))")) }
                continue
            }
            var b = book(path, .command, note: L("\(item.name): \(item.reason); \(item.detail)"), size: item.size)
            b.lastUsed = item.lastUsed
            b.idle = item.idle
            if path.hasPrefix(home + "/go/") || path == home + "/go/bin" {
                add(b, to: toolShelf("go"))
            } else {
                add(b, to: shelf("term:cli", .terminal, L("Command-line tools"), L("Commands not from Homebrew: downloaded by hand, bundled with installers, npm…")))
            }
        }

        for name in children(home) where name.hasPrefix(".") && ![".Trash", ".DS_Store"].contains(name) {
            let path = home + "/" + name
            guard let info = lookupDotfile(name) else {
                place(book(path, isDirectory(path) ? .folder : .file, note: L("Not in MacTidy's knowledge base yet")), id: String(name.dropFirst()), entry: String(name.dropFirst()))
                continue
            }
            let note = info.guess ? L("(Guess) \(info.what)") : info.what
            let tool = toolchain(named: name) ?? toolchain(named: info.owner)
            switch info.kind {
            case .system:
                add(book(path, .config, note: note), to: appleDataShelf())
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
                add(b, to: tool.map(toolShelf) ?? shelf("tool:other", .dev, L("Other toolchains"), L("Version managers and toolchains of other languages")))
            case .itemizedElsewhere:
                if name == ".cache" {
                    for child in children(path) where !child.hasPrefix(".") {
                        place(book(path + "/" + child, .cache, note: L("Cache in ~/.cache")), id: child, entry: child)
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
                    add(b, to: commandShelf(cmd))
                } else if info.apps.isEmpty && info.commands.isEmpty {
                    add(b, to: configs)
                } else {
                    orphanPool.append(OrphanEntry(id: name, isBundleID: false, alias: info.owner, note: L("\(info.owner) not found"), book: b))
                }
            }
        }
    }
}
