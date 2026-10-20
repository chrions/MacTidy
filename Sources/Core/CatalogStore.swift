import Foundation

/// Where the latest catalog lives, and how to produce a new one.
enum CatalogStore {
    static var home: String { fm.homeDirectoryForCurrentUser.path }
    static var directory: String { home + "/Library/Application Support/MacTidy" }
    static var path: String { directory + "/catalog.json" }

    static var exists: Bool { fm.fileExists(atPath: path) }

    static func load() -> Catalog? {
        guard let data = fm.contents(atPath: path) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Catalog.self, from: data)
    }

    static func encode(_ catalog: Catalog) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(catalog)
    }

    static func save(_ catalog: Catalog) throws {
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try encode(catalog).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    static func makeContext(staleDays: Int = 180) -> Context {
        let inventory = Inventory(home: home)
        let history = ShellHistory(historyFiles: [home + "/.zsh_history"],
                                   rcFiles: [home + "/.zshrc", home + "/.zprofile", home + "/.oh-my-zsh/lib/directories.zsh"])
        return Context(staleDays: staleDays, inventory: inventory, history: history)
    }

    /// Read-only scan of the whole Mac. Takes a minute or two, mostly measuring sizes.
    static func scan(progress: (String) -> Void) -> Catalog {
        progress(L("Listing apps and commands"))
        return CatalogBuilder(ctx: makeContext()).build(progress: progress)
    }
}
