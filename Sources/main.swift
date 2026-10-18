import Foundation

func log(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

var staleDays = 180
var outDir = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Desktop/MacTidy/reports")
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    switch a {
    case "--days": staleDays = args.popFirst().flatMap(Int.init) ?? staleDays
    case "--out": outDir = args.popFirst() ?? outDir
    case "-h", "--help":
        print("""
        mactidy：只读扫描这台 Mac，生成梳理报告

          --days N   超过 N 天没用算「很久没用」（默认 180）
          --out DIR  报告输出目录（默认 ~/Desktop/MacTidy/reports）
        """)
        exit(0)
    default:
        log("未知参数：\(a)")
        exit(2)
    }
}

func timed<T>(_ label: String, _ body: () -> T) -> T {
    let start = Date()
    let r = body()
    log(String(format: "  %@ %.1fs", label, Date().timeIntervalSince(start)))
    return r
}

log("正在扫描（只读）…")
let home = FileManager.default.homeDirectoryForCurrentUser.path
let inventory = timed("盘点应用和 PATH") { Inventory(home: home) }
let history = timed("解析命令历史") {
    ShellHistory(historyFiles: [home + "/.zsh_history"], rcFiles: [home + "/.zshrc", home + "/.zprofile", home + "/.oh-my-zsh/lib/directories.zsh"])
}
let ctx = Context(staleDays: staleDays, inventory: inventory, history: history)
let s = Scanners(ctx: ctx)

var items = [Item]()
items += timed("应用") { s.apps() }
items += timed("Homebrew") { s.brew() }
items += timed("其他命令行工具") { s.otherCLI() }
items += timed("开发环境") { s.devEnv() }
items += timed("主目录隐藏文件") { s.dotfiles() }
items += timed("软件残留") { s.leftovers() }
items += timed("后台服务") { s.launchItems() }
items += timed("缓存") { s.caches() }

let report = Report(ctx: ctx, items: items)
let stamp: String = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f.string(from: ctx.now)
}()
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let mdPath = "\(outDir)/report-\(stamp).md"
let jsonPath = "\(outDir)/report-\(stamp).json"
try report.markdown().write(toFile: mdPath, atomically: true, encoding: .utf8)
try report.json().write(to: URL(fileURLWithPath: jsonPath))

let counts = Dictionary(grouping: items, by: \.verdict).mapValues(\.count)
log("完成：共 \(items.count) 项，" + Verdict.allCases.map { "\($0.rawValue) \(counts[$0] ?? 0)" }.joined(separator: "，"))
print(mdPath)
