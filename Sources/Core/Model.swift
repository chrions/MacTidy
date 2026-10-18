import Foundation

enum Verdict: String, Codable, CaseIterable {
    case clean = "可清理"
    case review = "看情况"
    case unknown = "待识别"
    case keep = "保留"

    var order: Int {
        switch self {
        case .clean: return 0
        case .review: return 1
        case .unknown: return 2
        case .keep: return 3
        }
    }

    var badge: String {
        switch self {
        case .clean: return "🟢 可清理"
        case .review: return "🟡 看情况"
        case .unknown: return "⚪️ 待识别"
        case .keep: return "🔒 保留"
        }
    }
}

enum Section: String, Codable, CaseIterable {
    case apps = "应用"
    case brew = "Homebrew"
    case cli = "其他命令行工具"
    case devenv = "开发环境"
    case dotfiles = "主目录隐藏文件"
    case leftovers = "软件残留（~/Library）"
    case launch = "后台服务与开机启动"
    case caches = "缓存"
}

struct Item: Codable {
    var section: Section
    var name: String
    var path: String?
    var size: Int64?
    var lastUsed: Date?
    var lastUsedSource: String?
    var owner: String?
    var detail: String
    var verdict: Verdict
    var reason: String
    var suggestion: String?
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
