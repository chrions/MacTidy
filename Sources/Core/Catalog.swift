import Foundation
import IOKit

/// Top level of the library catalog.
enum Category: String, Codable, CaseIterable {
    case system, apps, dev, terminal, personal, orphans

    var name: String {
        switch self {
        case .system: return L("System")
        case .apps: return L("Apps")
        case .dev: return L("Development")
        case .terminal: return L("Terminal")
        case .personal: return L("My Files")
        case .orphans: return L("Orphans")
        }
    }

    var blurb: String {
        switch self {
        case .system: return L("Part of macOS. Shown, never touched.")
        case .apps: return L("Apps you installed, and the data they scattered around")
        case .dev: return L("Homebrew, Node, Go, Python and other toolchains")
        case .terminal: return L("Shell config, command-line tools, keys and histories")
        case .personal: return L("Photos, projects, documents and downloads you put here yourself")
        case .orphans: return L("The owner is gone, or can't be recognised")
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Category(rawValue: raw) ?? Category.legacy[raw] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown category \(raw)"))
        }
        self = value
    }

    /// Raw values written by version 0.2, which stored the Chinese names.
    private static let legacy: [String: Category] = [
        "系统": .system, "应用": .apps, "开发环境": .dev, "终端与命令": .terminal, "我的文件": .personal, "无主之物": .orphans,
    ]
}

enum BookKind: String, Codable, CaseIterable {
    case program, userData, sandbox, shared, cache, preferences, logs, windowState, webData, launch, helper, plugin,
         command, config, secret, history, toolchain, project, media, document, archive, folder, file

    var name: String {
        switch self {
        case .program: return L("Program")
        case .userData: return L("App data")
        case .sandbox: return L("Sandbox data")
        case .shared: return L("Shared data")
        case .cache: return L("Cache")
        case .preferences: return L("Preferences")
        case .logs: return L("Logs")
        case .windowState: return L("Window state")
        case .webData: return L("Web data")
        case .launch: return L("Launch service")
        case .helper: return L("Helper")
        case .plugin: return L("Plug-in")
        case .command: return L("Command")
        case .config: return L("Configuration")
        case .secret: return L("Keys & credentials")
        case .history: return L("History")
        case .toolchain: return L("Toolchain")
        case .project: return L("Code project")
        case .media: return L("Photos & videos")
        case .document: return L("Document")
        case .archive: return L("Installer or archive")
        case .folder: return L("Folder")
        case .file: return L("File")
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = BookKind(rawValue: raw) ?? BookKind.legacy[raw] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown kind \(raw)"))
        }
        self = value
    }

    /// Raw values written by version 0.2, which stored the Chinese names.
    private static let legacy: [String: BookKind] = [
        "程序本体": .program, "应用数据": .userData, "沙盒数据": .sandbox, "共享数据": .shared, "缓存": .cache,
        "偏好设置": .preferences, "日志": .logs, "窗口状态": .windowState, "网页数据": .webData, "开机服务": .launch,
        "帮助程序": .helper, "插件扩展": .plugin, "命令": .command, "配置": .config, "密钥与凭据": .secret,
        "历史记录": .history, "工具链": .toolchain, "代码项目": .project, "照片和视频": .media, "文档": .document,
        "安装包和压缩包": .archive, "文件夹": .folder, "文件": .file,
    ]
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
    /// Interface language at scan time; titles, summaries and notes are written in it.
    var language: String?
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
        return [sysctlString("hw.model"), sysctlString("machdep.cpu.brand_string")].compactMap { $0 }.joined(separator: ", ")
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
                era.name = names[beforeKey] ?? (machines > 1 ? L("Before the first Mac") : L("Before this Mac"))
            } else if let id = era.machineID {
                era.name = names[id] ?? (era.isCurrent ? machineDescription() : L("Mac #\(era.index)"))
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
