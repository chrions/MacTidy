import Foundation

let fm = FileManager.default

@discardableResult
func run(_ executable: String, _ args: [String], env: [String: String] = [:], timeout: TimeInterval = 120) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = args
    if !env.isEmpty {
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
    }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, "") }
    let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    killer.cancel()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// Allocated size in bytes for each path, computed with `du` in parallel.
func diskUsage(_ paths: [String]) -> [String: Int64] {
    let unique = Array(Set(paths))
    var result = [String: Int64]()
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: unique.count) { i in
        let r = run("/usr/bin/du", ["-sk", unique[i]], timeout: 300)
        let field = r.out.split(separator: "\t").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard let kb = Int64(field) else { return }
        lock.lock()
        result[unique[i]] = kb * 1024
        lock.unlock()
    }
    return result
}

func fillSizes(_ items: inout [Item]) {
    let paths = items.compactMap { $0.size == nil ? $0.path : nil }
    let sizes = diskUsage(paths)
    for i in items.indices where items[i].size == nil {
        if let p = items[i].path { items[i].size = sizes[p] }
    }
}

func exists(_ path: String) -> Bool { fm.fileExists(atPath: path) }

func isDirectory(_ path: String) -> Bool {
    var dir: ObjCBool = false
    return fm.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
}

func children(_ path: String) -> [String] {
    ((try? fm.contentsOfDirectory(atPath: path)) ?? []).sorted()
}

func modificationDate(_ path: String) -> Date? {
    (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
}

/// Newest modification time within `maxDepth` levels, a cheap proxy for "last touched".
func newestModification(_ path: String, maxDepth: Int = 2, limit: Int = 5000) -> Date? {
    var newest = modificationDate(path)
    guard isDirectory(path),
          let e = fm.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.contentModificationDateKey],
                                options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return newest }
    var seen = 0
    for case let url as URL in e {
        if e.level >= maxDepth { e.skipDescendants() }
        if let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           d > (newest ?? .distantPast), d < Date().addingTimeInterval(86_400) {
            newest = d
        }
        seen += 1
        if seen >= limit { break }
    }
    return newest
}

func isSymlink(_ path: String) -> Bool {
    ((try? fm.attributesOfItem(atPath: path))?[.type] as? FileAttributeType) == .typeSymbolicLink
}

func resolvedPath(_ path: String) -> String {
    (path as NSString).resolvingSymlinksInPath
}

func readPlist(_ path: String) -> [String: Any]? {
    guard let data = fm.contents(atPath: path) else { return nil }
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
}

func readText(_ path: String) -> String? {
    guard let data = fm.contents(atPath: path) else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func formatSize(_ bytes: Int64?) -> String {
    guard let bytes else { return "—" }
    if bytes == 0 { return "0" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func formatAge(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "无记录" }
    let days = Int(now.timeIntervalSince(date) / 86_400)
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    let ago: String
    switch days {
    case ..<1: ago = "今天"
    case ..<31: ago = "\(days) 天前"
    case ..<365: ago = "\(days / 30) 个月前"
    default: ago = String(format: "%.1f 年前", Double(days) / 365)
    }
    return "\(f.string(from: date))（\(ago)）"
}

func compareVersions(_ a: String, _ b: String) -> Bool {
    let pa = a.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    let pb = b.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    for (x, y) in zip(pa, pb) where x != y { return x < y }
    return pa.count < pb.count
}

func abbreviate(_ path: String, home: String) -> String {
    path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
