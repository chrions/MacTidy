import Foundation

func log(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

var outDir = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("reports")
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    switch a {
    case "--out": outDir = args.popFirst() ?? outDir
    case "-h", "--help":
        print("""
        mactidy: read-only scan of this Mac

          mactidy            Build the library catalog: who owns each thing, which Mac it came from,
                             and whether it has been used since moving here

          --out DIR  Output folder (default ./reports)
        """)
        exit(0)
    default:
        log("Unknown option: \(a)")
        exit(2)
    }
}

log("Scanning (read-only)…")
let home = FileManager.default.homeDirectoryForCurrentUser.path
let ctx = CatalogStore.makeContext()
let stamp: String = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f.string(from: ctx.now)
}()
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

var last = Date()
var lastLabel = ""
let catalog = CatalogBuilder(ctx: ctx).build { label in
    if !lastLabel.isEmpty { log(String(format: "  %@ %.1fs", lastLabel, Date().timeIntervalSince(last))) }
    (last, lastLabel) = (Date(), label)
}
log(String(format: "  %@ %.1fs", lastLabel, Date().timeIntervalSince(last)))
let report = CatalogReport(catalog: catalog, home: home)
let mdPath = "\(outDir)/catalog-\(stamp).md"
try report.markdown().write(toFile: mdPath, atomically: true, encoding: .utf8)
try report.json().write(to: URL(fileURLWithPath: "\(outDir)/catalog-\(stamp).json"))
try CatalogStore.save(catalog)
print(report.summary())
print("\nFull catalog: \(mdPath)")
