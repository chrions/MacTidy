import CoreServices
import Foundation

private let mediaExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp", "raw", "cr2", "cr3",
                                      "nef", "arw", "dng", "raf", "orf", "rw2", "mov", "mp4", "m4v", "avi", "mkv", "mts", "3gp",
                                      "mp3", "m4a", "wav", "flac", "aac", "aiff", "psd"]
private let docExts: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "txt", "md",
                                    "csv", "rtf", "epub", "xmind", "json", "yml", "yaml", "xml", "html", "sql", "log"]
private let archiveExts: Set<String> = ["dmg", "pkg", "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "iso", "whl", "jar", "apk", "ipa"]
private let projectMarkers = [".git", "package.json", "go.mod", "pom.xml", "build.gradle", "Cargo.toml", "pyproject.toml",
                              "requirements.txt", "setup.py", "composer.json", "Gemfile", "CMakeLists.txt", "Makefile",
                              "docker-compose.yml", "docker-compose.yaml", "Dockerfile", "project.config.json", "manifest.json"]
private let mediaBundles: Set<String> = ["photoslibrary", "photolibrary", "fcpbundle", "imovielibrary", "tvlibrary", "musiclibrary"]

extension CatalogBuilder {
    /// Personal files in the home folder: each top-level item, plus the contents of the standard folders.
    func addPersonal() {
        let standard: [(String, String)] = ["Desktop", "Documents", "Downloads", "Movies", "Pictures", "Music"].map {
            ($0, fm.displayName(atPath: home + "/" + $0))
        }
        let skip = Set(["Library", "Applications", "Public", "go", "bin", ColdStorage.folderName] + standard.map(\.0))
        let pathDirs = Set(inv.pathDirs)
        for name in children(home) where !name.hasPrefix(".") && !skip.contains(name) && !pathDirs.contains(home + "/" + name) {
            addPersonal(home + "/" + name, location: L("the home folder"))
        }
        for (folder, label) in standard {
            for name in children(home + "/" + folder) where !name.hasPrefix(".") && name != "Icon\r" {
                addPersonal(home + "/" + folder + "/" + name, location: label)
            }
        }
    }

    private func addPersonal(_ path: String, location: String) {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        if looksSensitive(name) {
            add(book(path, .secret, note: L("In \(location); the name looks like a private key, certificate or password (contents not read)")),
                to: shelf("mine:secret", .personal, L("Stray keys and passwords"), L("Files named like private keys, certificates or passwords; better kept together somewhere safe")))
            return
        }
        let kind = classify(path, ext: ext)
        let (id, title, summary): (String, String, String)
        switch kind {
        case .project: (id, title, summary) = ("mine:project", L("Code projects"), L("Project folders marked by Git, package.json, go.mod and the like"))
        case .media: (id, title, summary) = ("mine:media", L("Photos & videos"), L("Photos, videos, music and media libraries"))
        case .document: (id, title, summary) = ("mine:document", L("Documents & spreadsheets"), L("PDFs, Office documents, spreadsheets, text and exported data"))
        case .archive: (id, title, summary) = ("mine:archive", L("Installers & archives"), L("dmg / pkg installers and archives; usually safe to delete once installed or extracted"))
        case .folder: (id, title, summary) = ("mine:folder", L("Other folders"), L("Folders of no particular type"))
        default: (id, title, summary) = ("mine:file", L("Other files"), L("Scripts, config snippets and other loose files"))
        }
        var b = book(path, kind, note: L("In \(location)"))
        b.lastUsed = spotlightLastUsed(path)
        add(b, to: shelf(id, .personal, title, summary))
    }

    /// When the file was last opened, as recorded by Spotlight (survives migration as an extended attribute).
    private func spotlightLastUsed(_ path: String) -> Date? {
        guard let md = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(md, kMDItemLastUsedDate) as? Date
    }

    private func looksSensitive(_ name: String) -> Bool {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        if ["pem", "key", "p12", "pfx", "keystore", "jks", "ppk"].contains(ext) { return true }
        return ["privatekey", "private_key", "password", "passwd", "id_rsa", "id_ed25519", "secret", "credential", "token"]
            .contains { lower.contains($0) }
    }

    private func classify(_ path: String, ext: String) -> BookKind {
        if mediaBundles.contains(ext) { return .media }
        guard isDirectory(path), !ext.hasSuffix("app") else {
            if mediaExts.contains(ext) { return .media }
            if docExts.contains(ext) { return .document }
            if archiveExts.contains(ext) { return .archive }
            return .file
        }
        if projectMarkers.contains(where: { exists(path + "/" + $0) }) || children(path).contains(where: { $0.hasSuffix(".xcodeproj") }) {
            return .project
        }
        // Folders: look at a sample of the files inside.
        var counts = [BookKind: Int]()
        var seen = 0
        if let e = fm.enumerator(atPath: path) {
            while let rel = e.nextObject() as? String, seen < 400 {
                let comps = rel.split(separator: "/")
                if comps.count > 3 { e.skipDescendants(); continue }
                if comps.last.map({ projectMarkers.contains(String($0)) }) == true, comps.count <= 2 { return .project }
                let x = (rel as NSString).pathExtension.lowercased()
                if mediaExts.contains(x) { counts[.media, default: 0] += 1 }
                else if docExts.contains(x) { counts[.document, default: 0] += 1 }
                else if archiveExts.contains(x) { counts[.archive, default: 0] += 1 }
                else if !x.isEmpty { counts[.file, default: 0] += 1 }
                seen += 1
            }
        }
        let total = counts.values.reduce(0, +)
        guard total > 0, let (top, n) = counts.max(by: { $0.value < $1.value }), Double(n) / Double(total) >= 0.6, top != .file else {
            return .folder
        }
        return top
    }
}
