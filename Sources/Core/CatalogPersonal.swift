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
        let standard: [(String, String)] = [("Desktop", "桌面"), ("Documents", "文稿"), ("Downloads", "下载"), ("Movies", "影片"),
                                            ("Pictures", "图片"), ("Music", "音乐")]
        let skip = Set(["Library", "Applications", "Public", "go", "bin"] + standard.map(\.0))
        let pathDirs = Set(inv.pathDirs)
        for name in children(home) where !name.hasPrefix(".") && !skip.contains(name) && !pathDirs.contains(home + "/" + name) {
            addPersonal(home + "/" + name, location: "主目录")
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
            add(book(path, .secret, note: "放在\(location)；从文件名看像是私钥、证书或密码（没有读取内容）"),
                to: shelf("mine:secret", .personal, "散落的密钥和密码", "文件名像私钥、证书或密码的文件，建议集中放到安全的地方"))
            return
        }
        let kind = classify(path, ext: ext)
        let (id, title, summary): (String, String, String)
        switch kind {
        case .project: (id, title, summary) = ("mine:project", "代码项目", "带有 Git、package.json、go.mod 等标记的项目文件夹")
        case .media: (id, title, summary) = ("mine:media", "照片和视频", "照片、视频、音乐和媒体资料库")
        case .document: (id, title, summary) = ("mine:document", "文档和表格", "PDF、Office 文档、表格、文本和导出的数据")
        case .archive: (id, title, summary) = ("mine:archive", "安装包和压缩包", "dmg / pkg 安装包和各种压缩包，装完或解压后通常可以删")
        case .folder: (id, title, summary) = ("mine:folder", "其他文件夹", "看不出类型的文件夹")
        default: (id, title, summary) = ("mine:file", "其他文件", "脚本、配置片段等零散文件")
        }
        var b = book(path, kind, note: "放在\(location)")
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
