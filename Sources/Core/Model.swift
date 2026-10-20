import Foundation

enum Verdict: String, Codable {
    case clean, review, unknown, keep
}

/// One finding of a scanner, before it is placed on a shelf.
struct Item {
    var name: String
    var path: String?
    var size: Int64?
    var lastUsed: Date?
    var owner: String?
    var detail: String
    var verdict: Verdict
    var reason: String
    /// Toolchain it belongs to (`node`, `python`...), for runtime versions.
    var tool: String?
    /// Known to be out of use: a version that isn't the active one, a shadowed command, a dangling link.
    var idle = false
    /// A PATH entry that points nowhere; reported on the shell shelf rather than as a book.
    var missingDirectory = false
    var cask = false
}

struct Context {
    let now = Date()
    let staleDays: Int
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let inventory: Inventory
    let history: ShellHistory

    func isStale(_ date: Date?) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) > Double(staleDays) * 86_400
    }

    func path(_ relative: String) -> String {
        (home as NSString).appendingPathComponent(relative)
    }
}
