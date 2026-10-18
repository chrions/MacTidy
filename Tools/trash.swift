import Foundation

// Moves each argument to the Trash via Finder's mechanism, so "Put Back" works.
var failed = 0
for path in CommandLine.arguments.dropFirst() {
    let expanded = (path as NSString).expandingTildeInPath
    guard FileManager.default.fileExists(atPath: expanded) else {
        print("跳过（不存在）\t\(path)")
        continue
    }
    do {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: expanded), resultingItemURL: nil)
        print("已移到废纸篓\t\(path)")
    } catch {
        failed += 1
        print("失败\t\(path)\t\(error.localizedDescription)")
    }
}
exit(failed == 0 ? 0 : 1)
