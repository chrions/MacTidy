import AppKit

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var lines: [String] { split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty } }
}

/// Finds Homebrew packages, other command-line tools, language runtimes and launch services.
struct Scanners {
    let ctx: Context
    private var inv: Inventory { ctx.inventory }
    private var hist: ShellHistory { ctx.history }

    private func list(_ names: some Sequence<String>) -> String { ListFormatter.localizedString(byJoining: Array(names)) }

    /// Verdict for something whose usage is only knowable from shell history.
    private func commandVerdict(_ names: [String]) -> (Verdict, String, Date?) {
        guard !names.isEmpty else {
            return (.review, L("No commands of its own; probably a library used by other programs"), nil)
        }
        let shown = list(names.prefix(3))
        guard let use = hist.lastUse(of: names) else {
            return (.review, L("\(shown) never appears in the command history"), nil)
        }
        if ctx.isStale(use.last) {
            return (.review, L("\(shown) not used for over \(ctx.staleDays) days"), use.last)
        }
        return (.keep, L("Used recently (\(use.count) times in total)"), use.last)
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
            items.append(Item(name: short, path: "\(prefix)/Cellar/\(short)", lastUsed: last,
                              detail: bins.isEmpty ? L("Installed on purpose") : L("Provides \(list(bins.prefix(6)))"),
                              verdict: verdict, reason: reason))
        }

        for cask in run(brewPath, ["list", "--cask"], env: env).out.lines {
            let app = inv.findApp([cask, cask.replacingOccurrences(of: "-", with: " ")])
            let stale = ctx.isStale(app?.lastUsed)
            items.append(Item(name: cask, path: "\(prefix)/Caskroom/\(cask)", lastUsed: app?.lastUsed,
                              detail: app.map { L("Installs \($0.name)") } ?? L("App"),
                              verdict: stale ? .review : .keep, reason: stale ? L("Its app hasn't been opened in a long time") : L("Used recently"),
                              cask: true))
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
            return .package(display: L("Global npm package \(pkg)"), root: String(target[..<r.upperBound]) + pkg)
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
                    items.append(Item(name: name, path: full, size: 0, detail: L("Link to \(dest)"), verdict: .clean,
                                      reason: L("The program it points to is gone; left over from an uninstall"), idle: true))
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
            let shownBins = names.count > 8 ? L("\(list(names.prefix(8))) and \(names.count - 8) more") : list(names)
            var detail = L("Commands: \(shownBins)")
            if !shadowed.isEmpty {
                let examples = shadowed.prefix(3).map { L("\($0.name) runs \(abbreviate(inv.commands[$0.name] ?? "?", home: ctx.home))") }
                detail += L("; shadowed: \(list(examples))")
            }

            var verdict: Verdict
            var reason: String
            var last: Date?
            var path = g.bins[0].path
            var display = names.count == 1 ? names[0] : L("\(names[0]) and others")

            switch g.origin {
            case .app(let appPath):
                let app = inv.apps.first { $0.path == appPath }
                display = L("Commands that come with \((appPath as NSString).lastPathComponent)")
                (verdict, reason) = (.keep, L("Installed with \(app?.name ?? appPath); goes wherever the app goes"))
                last = hist.lastUse(of: names)?.last
                items.append(Item(name: display, path: appPath, size: 0, lastUsed: last, owner: app?.name, detail: detail,
                                  verdict: verdict, reason: reason))
                continue
            case .package(let d, let root):
                display = d
                path = root
            default:
                break
            }

            var idle = false
            if active.isEmpty {
                (verdict, reason) = (.clean, L("All shadowed by commands of the same name earlier on PATH; these never run"))
                last = nil
                idle = true
            } else {
                (verdict, reason, last) = commandVerdict(active)
                if !shadowed.isEmpty { reason += L("; \(shadowed.count) more are shadowed by commands of the same name") }
            }
            items.append(Item(name: display, path: path, lastUsed: last, detail: detail, verdict: verdict, reason: reason, idle: idle))
        }

        // Never-used standalone programs pile up (e.g. `go install`ed examples); one row per folder.
        fillSizes(&items)
        let neverUsed = items.filter { $0.verdict == .review && $0.lastUsed == nil && groups["file:" + ($0.path ?? "")] != nil }
        if neverUsed.count > 1 {
            let byDir = Dictionary(grouping: neverUsed) { (($0.path ?? "") as NSString).deletingLastPathComponent }
            let folded = Set(neverUsed.compactMap(\.path))
            items.removeAll { folded.contains($0.path ?? "") && $0.verdict == .review && $0.lastUsed == nil }
            for (dir, group) in byDir.sorted(by: { $0.key < $1.key }) {
                items.append(Item(name: L("\(group.count) never-used programs in \(abbreviate(dir, home: ctx.home))"), path: dir,
                                  size: group.compactMap(\.size).reduce(0, +),
                                  detail: list(group.sorted { ($0.size ?? 0) > ($1.size ?? 0) }.map(\.name)),
                                  verdict: .review,
                                  reason: L("Never appears in the command history (programs run by scripts or other apps leave no trace)")))
            }
        }

        for missing in inv.missingPathDirs {
            let source = pathDefinition(of: missing)
            items.append(Item(name: L("Missing folder on PATH: \(abbreviate(missing, home: ctx.home))"), path: missing, size: 0,
                              detail: source.map { L("Set in \($0)") } ?? L("Not set in your shell files (maybe /etc/paths.d or another script)"),
                              verdict: .clean,
                              reason: L("The folder doesn't exist, so every command lookup checks it for nothing"),
                              missingDirectory: true))
        }
        fillSizes(&items)
        return items
    }

    private func pathDefinition(of dir: String) -> String? {
        let variants = [dir, dir.replacingOccurrences(of: ctx.home, with: "$HOME"), dir.replacingOccurrences(of: ctx.home, with: "~")]
        for rc in [".zshrc", ".zprofile", ".zshenv", ".bash_profile", ".bashrc", ".profile"] {
            guard let text = readText(ctx.path(rc)) else { continue }
            for (n, line) in text.components(separatedBy: "\n").enumerated() where variants.contains(where: line.contains) {
                return L("~/\(rc), line \(n + 1)")
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
        let usedText = stillUsed.isEmpty ? L("None of its commands are still in use.")
            : L("Still in use: \(list(stillUsed)) (reinstall them with the new Homebrew before removing this one).")
        return Item(name: L("Old Intel Homebrew (\(root))"), path: root + "/Homebrew", size: sizes.values.reduce(0, +), lastUsed: newest,
                    detail: L("\(formulae.count) packages built for Intel, running under Rosetta; usually brought over from an Intel Mac. \(usedText)"),
                    verdict: stillUsed.isEmpty ? .clean : .review,
                    reason: L("You now use the Apple silicon Homebrew in \(activePrefix); two side by side are easy to mix up"))
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
            items.append(Item(name: L("Node versions downloaded by n (/usr/local/n)"), path: "/usr/local/n",
                              detail: L("Versions kept by the n version manager: \(list(children("/usr/local/n/versions/node")))"),
                              verdict: inUse ? .keep : .clean,
                              reason: inUse ? L("The current node comes from n") : L("You manage Node with nvm now; these versions from n go unused"),
                              tool: "node", idle: !inUse))
        }
        guard !versions.isEmpty else { return items }
        let alias = readText(nvm + "/alias/default") ?? "node"
        let numeric = alias.hasPrefix("v") ? String(alias.dropFirst()) : alias
        let defaultVersion = versions.last { $0 == "v" + numeric || $0.hasPrefix("v" + numeric + ".") } ?? versions.last!

        for v in versions {
            let dir = "\(root)/\(v)"
            let isDefault = v == defaultVersion || (activeNode?.hasPrefix(dir + "/") ?? false)
            let globals = npmGlobals(dir + "/lib/node_modules")
            items.append(Item(name: "Node.js \(v)", path: dir,
                              detail: globals.isEmpty ? L("Installed by nvm") : L("Installed by nvm; global packages: \(list(globals.map(\.name)))"),
                              verdict: isDefault ? .keep : .review,
                              reason: isDefault ? L("nvm's default version (alias default = \(alias))")
                                  : L("Not the default; can go unless a project pins it in .nvmrc"),
                              tool: "node", idle: !isDefault))
        }
        return items
    }

    private func npmGlobals(_ modules: String) -> [(name: String, path: String)] {
        var names = [String]()
        for entry in children(modules) where !entry.hasPrefix(".") {
            if entry.hasPrefix("@") {
                names += children(modules + "/" + entry).map { "\(entry)/\($0)" }
            } else {
                names.append(entry)
            }
        }
        return names.filter { !["npm", "corepack"].contains($0) }.map { ($0, modules + "/" + $0) }
    }

    private func ruby() -> [Item] {
        let root = ctx.path(".rbenv/versions")
        let versions = children(root).sorted(by: compareVersions)
        guard !versions.isEmpty else { return [] }
        let global = readText(ctx.path(".rbenv/version")) ?? "system"
        return versions.map { v in
            let isDefault = v == global
            return Item(name: "Ruby \(v)", path: "\(root)/\(v)", detail: L("Installed by rbenv"),
                        verdict: isDefault ? .keep : .review,
                        reason: isDefault ? L("rbenv's global default") : L("Not rbenv's default (that is \(global))"),
                        tool: "ruby", idle: !isDefault)
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
            let stale = ctx.isStale(use?.last)
            items.append(Item(name: L("Python \(v) (python.org installer)"), path: dir, lastUsed: use?.last,
                              detail: L("Installed in /Library/Frameworks, with /Applications/Python \(v)"),
                              verdict: isDefault && !stale ? .keep : .review,
                              reason: isDefault ? (stale ? L("The current python3, but not used in a long time") : L("The current python3"))
                                  : L("Not the current python3"),
                              tool: "python", idle: !isDefault))
        }
        let pyenv = ctx.path(".pyenv/versions")
        let pyGlobal = readText(ctx.path(".pyenv/version")) ?? ""
        for v in children(pyenv) {
            let isDefault = pyGlobal.lines.contains(v)
            items.append(Item(name: "Python \(v) (pyenv)", path: "\(pyenv)/\(v)", detail: L("Installed by pyenv"),
                              verdict: isDefault ? .keep : .review, reason: isDefault ? L("pyenv's default") : L("Not pyenv's default"),
                              tool: "python", idle: !isDefault))
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
            let stale = ctx.isStale(use?.last)
            return Item(name: "JDK \(jdk)", path: dir, lastUsed: use?.last, detail: L("Java Development Kit"),
                        verdict: isDefault && !stale ? .keep : .review,
                        reason: isDefault ? (stale ? L("The current JDK, but java, javac, mvn and gradle haven't been used for over \(ctx.staleDays) days")
                                                   : L("The current JDK"))
                            : L("Not the current JDK"),
                        tool: "java", idle: !isDefault)
        }
    }

    private func golang() -> [Item] {
        let root = "/usr/local/go"
        guard exists(root) else { return [] }
        let version = readText(root + "/VERSION")?.lines.first ?? "Go"
        let (verdict, reason, last) = commandVerdict(["go"])
        return [Item(name: version, path: root, lastUsed: last, detail: L("The official installer puts Go in /usr/local/go"),
                     verdict: verdict, reason: reason, tool: "go")]
    }

    // MARK: Launch agents & daemons

    func launchItems() -> [Item] {
        let dirs: [(path: String, kind: String)] = [
            (ctx.path("Library/LaunchAgents"), L("Starts when you log in")),
            ("/Library/LaunchAgents", L("Starts when any user logs in")),
            ("/Library/LaunchDaemons", L("System service, runs from startup")),
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
                    (verdict, reason) = (.clean, L("The program it runs (\(abbreviate(checkPath ?? "", home: ctx.home))) is gone; a leftover that fails at every startup"))
                } else if ownerName == nil {
                    (verdict, reason) = (.review, L("No matching app found; possibly a helper left behind by an uninstall"))
                } else if let app = ownerApp, !app.isApple, ctx.isStale(app.lastUsed) {
                    (verdict, reason) = (.review, L("\(app.name) hasn't been opened in a long time, but its background service keeps running"))
                } else {
                    (verdict, reason) = (.keep, L("\(ownerName!) is still installed"))
                }
                let programText = program.map { abbreviate($0, home: ctx.home) } ?? L("located by the system from its bundle")
                items.append(Item(name: label, path: plistPath, size: 0, lastUsed: ownerApp?.lastUsed, owner: ownerName,
                                  detail: L("\(dir.kind); program: \(programText)") + ((dict["Disabled"] as? Bool) == true ? L("; disabled") : ""),
                                  verdict: verdict, reason: reason))
            }
        }
        return items
    }
}
