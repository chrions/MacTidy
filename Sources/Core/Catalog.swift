import Foundation
import IOKit

/// Top level of the library catalog.
enum Category: String, Codable, CaseIterable {
    case system = "系统"
    case apps = "应用"
    case dev = "开发环境"
    case terminal = "终端与命令"
    case personal = "我的文件"
    case orphans = "无主之物"

    var blurb: String {
        switch self {
        case .system: return "macOS 自带的东西，只看不动"
        case .apps: return "你安装的应用，以及它们散落在各处的数据"
        case .dev: return "Homebrew、Node、Go、Python 等开发工具链"
        case .terminal: return "shell 配置、命令行工具、密钥和历史记录"
        case .personal: return "你自己放进来的照片、项目、文档和下载"
        case .orphans: return "主人已经不在了，或者认不出是谁的"
        }
    }
}

enum BookKind: String, Codable {
    case program = "程序本体"
    case userData = "应用数据"
    case sandbox = "沙盒数据"
    case shared = "共享数据"
    case cache = "缓存"
    case preferences = "偏好设置"
    case logs = "日志"
    case windowState = "窗口状态"
    case webData = "网页数据"
    case launch = "开机服务"
    case helper = "帮助程序"
    case plugin = "插件扩展"
    case command = "命令"
    case config = "配置"
    case secret = "密钥与凭据"
    case history = "历史记录"
    case toolchain = "工具链"
    case project = "代码项目"
    case media = "照片和视频"
    case document = "文档"
    case archive = "安装包和压缩包"
    case folder = "文件夹"
    case file = "文件"
}

/// One period of the user's history: the time a particular Mac was in use.
struct Era: Codable {
    var index: Int
    var name: String
    var start: Date?
    var end: Date?
    var machineID: String?
    var isCurrent: Bool
}

/// Something that can be handled as a whole: a file or folder at one path.
struct Book: Codable {
    var path: String
    var kind: BookKind
    var size: Int64?
    var created: Date?
    var modified: Date?
    var note: String?
    /// Needs administrator rights or is protected by macOS.
    var protected = false
    var era: Int?
    /// Lies inside another book on the same shelf, so its size is already counted there.
    var nested = false
    /// Explicit evidence of use: command history, Spotlight "last opened".
    var lastUsed: Date?
    /// Known to be out of use, e.g. a runtime version that isn't the active one or a command shadowed on PATH.
    var idle = false

    /// Kinds that get written to whenever their owner runs, so a recent modification means use.
    /// Configs, programs and toolchains are only read, and reads leave no reliable trace.
    var writtenWhenUsed: Bool {
        [.userData, .sandbox, .shared, .cache, .preferences, .logs, .windowState, .webData, .history,
         .project, .document, .media, .folder, .file, .archive].contains(kind)
    }

    var activity: Date? {
        [lastUsed, writtenWhenUsed ? modified : nil].compactMap { $0 }.max()
    }
}

/// Everything that belongs to one owner: an app, a toolchain, a group of personal files...
struct Shelf: Codable {
    var id: String
    var category: Category
    var title: String
    var summary: String
    var books: [Book] = []
    var lastUsed: Date?
    var lastUsedSource: String?
    var flags: [String] = []
    var verdict: Verdict?
    var reason: String?

    var size: Int64 = 0
    var firstSeen: Date?
    var era: Int?
    var lastActive: Date?
    var usedSinceArrival: Bool?
}

struct Catalog: Codable {
    var generatedAt: Date
    var machine: String
    var eras: [Era]
    var shelves: [Shelf]
    var notes: [String]
}

// MARK: - Eras

enum Eras {
    /// Each Mac that ever logged into this account leaves `~/Library/Keychains/<hardware UUID>`, and
    /// Migration Assistant carries those folders along, so their creation dates mark when each Mac arrived.
    static func detect(home: String) -> [Era] {
        let current = hardwareUUID()
        let keychains = home + "/Library/Keychains"
        let uuid = #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#
        var machines = children(keychains)
            .filter { $0.range(of: uuid, options: .regularExpression) != nil }
            .compactMap { id -> (id: String, start: Date)? in creationDate(keychains + "/" + id).map { (id, $0) } }
            .sorted { $0.start < $1.start }
        if let current, !machines.contains(where: { $0.id == current }) {
            machines.append((current, creationDate(home + "/Library") ?? Date()))
        }
        var eras = [Era(index: 0, name: "", start: nil, end: machines.first?.start, machineID: nil, isCurrent: false)]
        for (i, m) in machines.enumerated() {
            eras.append(Era(index: i + 1, name: "", start: m.start, end: i + 1 < machines.count ? machines[i + 1].start : nil,
                            machineID: m.id, isCurrent: m.id == current))
        }
        return named(eras)
    }

    /// Dates before Mac OS X are placeholders from archives and updaters (e.g. 1980-01-01 in zip files).
    static let earliestPlausible = Date(timeIntervalSince1970: 978_307_200)

    static func era(of date: Date?, in eras: [Era]) -> Int? {
        guard let date, date > earliestPlausible,
              var index = eras.last(where: { ($0.start ?? .distantPast) <= date })?.index else { return nil }
        // Migration Assistant recreates folders on the day it runs; whatever appeared that day came from the previous Mac.
        if isMigrationDay(date, eras: eras) { index -= 1 }
        return index
    }

    static func isMigrationDay(_ date: Date, eras: [Era]) -> Bool {
        eras.contains { era in
            guard era.index >= 2, let start = era.start else { return false }
            return date >= start && date < start.addingTimeInterval(86_400)
        }
    }

    /// When macOS was first installed on this Mac (at the factory), from the installer history.
    static func systemInstallDate() -> Date? {
        guard let data = fm.contents(atPath: "/Library/Receipts/InstallHistory.plist"),
              let list = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]] else { return nil }
        return list.compactMap { $0["date"] as? Date }.min()
    }

    /// Apple's marketing name, e.g. "MacBook Pro (14-inch, Nov 2024)"; model identifier and CPU on older Macs.
    static func machineDescription() -> String {
        let product = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        defer { if product != 0 { IOObjectRelease(product) } }
        if product != 0, let data = IORegistryEntryCreateCFProperty(product, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data,
           let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces)),
           !name.isEmpty {
            return name
        }
        return [sysctlString("hw.model"), sysctlString("machdep.cpu.brand_string")].compactMap { $0 }.joined(separator: "，")
    }

    /// Key for the period before the first known Mac in eras.json.
    static let beforeKey = "before"

    /// Default names, overridden by whatever the user called each Mac. Applied on every load, so renaming needs no rescan.
    static func named(_ eras: [Era]) -> [Era] {
        let names = loadNames()
        let machines = eras.filter { $0.machineID != nil }.count
        return eras.map { era in
            var era = era
            if era.index == 0 {
                era.name = names[beforeKey] ?? (machines > 1 ? "第一台 Mac 之前" : "这台 Mac 之前")
            } else if let id = era.machineID {
                era.name = names[id] ?? (era.isCurrent ? machineDescription() : "第 \(era.index) 台 Mac")
            }
            return era
        }
    }

    /// Saves a user-given name for an era; an empty name goes back to the default.
    static func rename(_ era: Era, to name: String) {
        guard let key = era.index == 0 ? beforeKey : era.machineID else { return }
        var names = loadNames()
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[key] = clean.isEmpty ? nil : clean
        try? fm.createDirectory(atPath: namesPath.deletingLastPathComponent, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(names).write(to: URL(fileURLWithPath: namesPath as String), options: .atomic)
    }

    private static var namesPath: NSString {
        (fm.homeDirectoryForCurrentUser.path + "/Library/Application Support/MacTidy/eras.json") as NSString
    }

    /// User-given names keyed by hardware UUID (or `before`), in ~/Library/Application Support/MacTidy/eras.json.
    private static func loadNames() -> [String: String] {
        guard let data = fm.contents(atPath: namesPath as String) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

func creationDate(_ path: String) -> Date? {
    (try? fm.attributesOfItem(atPath: path))?[.creationDate] as? Date
}
