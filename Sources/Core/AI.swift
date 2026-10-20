import Foundation
import Security

/// Where to send recognition requests: any OpenAI-compatible chat completions endpoint.
struct AIConfig: Codable, Equatable {
    var baseURL = ""
    var model = ""
    /// Words replaced with *** before anything is sent, e.g. the user's real name.
    var blockedWords: [String]?

    struct Preset {
        let name: String
        let baseURL: String
        let model: String
        let needsKey: Bool
    }

    static let presets = [
        Preset(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", needsKey: true),
        Preset(name: "通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", needsKey: true),
        Preset(name: "Kimi", baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k", needsKey: true),
        Preset(name: "智谱", baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash", needsKey: true),
        Preset(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", needsKey: true),
        Preset(name: "本机 Ollama", baseURL: "http://localhost:11434/v1", model: "qwen2.5", needsKey: false),
    ]

    static var path: String { CatalogStore.directory + "/ai.json" }

    var isComplete: Bool { !baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !model.trimmingCharacters(in: .whitespaces).isEmpty }

    var isLocal: Bool {
        guard let host = URL(string: baseURL)?.host else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(host) || host.hasSuffix(".local")
    }

    static func load() -> AIConfig {
        fm.contents(atPath: path).flatMap { try? JSONDecoder().decode(AIConfig.self, from: $0) } ?? AIConfig()
    }

    func save() {
        try? fm.createDirectory(atPath: CatalogStore.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: URL(fileURLWithPath: AIConfig.path), options: .atomic)
    }
}

/// Keeps personal details out of what gets sent.
enum AIPrivacy {
    /// Names that suggest identity documents, finances or credentials; such items aren't sent at all.
    private static let sensitive = #"(?i)简历|身份证|证件|护照|户口|学籍|学历|学位|毕业证|成绩|体检|病历|合同|协议|银行|流水|工资|社保|公积金|税|发票|密码|口令|私钥|密钥|凭证|证书|api[-_ ]?key|token|secret|passw|credential|private|\.pem$|\.p12$|\.key$|id_rsa|id_ed25519"#

    static func isSensitive(_ name: String) -> Bool {
        name.range(of: sensitive, options: .regularExpression) != nil
    }

    /// Masks long digit runs (phone and ID numbers) and the user's blocked words.
    static func clean(_ text: String, blocked: [String]) -> String {
        var s = text.replacingOccurrences(of: #"\d{7,}"#, with: "<数字>", options: .regularExpression)
        for w in blocked where !w.isEmpty { s = s.replacingOccurrences(of: w, with: "***", options: .caseInsensitive) }
        return s
    }
}

/// The API key lives in the login keychain, one per endpoint, never in a plain file.
enum AIKey {
    private static let service = "MacTidy AI"

    static func read(for baseURL: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: baseURL, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String, for baseURL: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: baseURL]
        SecItemDelete(q as CFDictionary)
        guard !key.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrLabel as String] = "MacTidy AI 识别的 API key"
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// What the AI made of one shelf or one item.
struct AINote: Codable {
    var what: String
    var owner: String?
    /// Finer grouping for personal files, e.g. 工作文档 / 学习资料.
    var group: String?
    /// 保留 / 冷藏 / 可以删
    var advice: String?
    var reason: String?
    var model: String
    var date: Date
}

/// Something to be recognised: only names, paths and metadata, never file contents.
struct AISubject: Encodable {
    var id: String
    var title: String
    var category: String
    var summary: String
    var paths: [String]
    var kinds: [String]
    var size: String
    var cameFrom: String
    var lastActive: String
    var usedSinceArrival: String
}

enum AINotes {
    static var path: String { CatalogStore.directory + "/ai-notes.json" }

    static func load() -> [String: AINote] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return fm.contents(atPath: path).flatMap { try? dec.decode([String: AINote].self, from: $0) } ?? [:]
    }

    static func save(_ notes: [String: AINote]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try? fm.createDirectory(atPath: CatalogStore.directory, withIntermediateDirectories: true)
        try? enc.encode(notes).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct AIClient {
    let config: AIConfig
    let key: String?

    static let batchSize = 12

    private static let instructions = """
    你是 macOS 专家，在帮用户整理一台 Mac，它可能用「迁移助理」从以前的 Mac 搬过来过一次或多次，积累了很多来历不明的东西。
    用户会给你一组条目，每个条目只有名称、路径和元数据，没有文件内容。对每个条目判断：
    - owner：它是哪个应用、开发商或工具留下的；用户自己的文件写「用户本人」；认不出写 null。
    - what：它是干什么的，一两句具体的中文，不要复述路径。
    - group：只对「我的文件」类别填写一个细分类，比如 工作文档、学习资料、设计素材、照片视频、安装包、代码项目、备份、临时文件、游戏、音乐；其他类别写 null。
    - advice：保留、冷藏、可以删 三选一。在用、重要或拿不准的选保留或冷藏；明确是卸载残留、缓存、过期安装包的才选可以删。
    - reason：一句话理由。
    只根据给出的信息推断，拿不准就直说拿不准，不要编造。
    只输出 JSON，不要任何其他文字：{"items":[{"id":"…","owner":"…","what":"…","group":null,"advice":"保留","reason":"…"}]}
    """

    func recognise(_ subjects: [AISubject]) async throws -> [String: AINote] {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let payload = String(data: try enc.encode(subjects), encoding: .utf8) ?? "[]"
        let content = try await chat([
            ["role": "system", "content": AIClient.instructions],
            ["role": "user", "content": "请识别这些条目：\n" + payload],
        ])
        return try parse(content, ids: Set(subjects.map(\.id)))
    }

    /// A tiny request to check the address, model and key.
    func test() async throws -> String {
        try await chat([["role": "user", "content": "只回复两个字：可以"]], maxTokens: 10)
    }

    private func chat(_ messages: [[String: String]], maxTokens: Int? = nil) async throws -> String {
        let base = config.baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base.hasSuffix("/chat/completions") ? base : base + "/chat/completions") else {
            throw AIError(message: "接口地址不对")
        }
        var req = URLRequest(url: url, timeoutInterval: 180)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = ["model": config.model.trimmingCharacters(in: .whitespaces), "messages": messages, "temperature": 0.2]
        if let maxTokens { body["max_tokens"] = maxTokens }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200..<300).contains(status) else {
            let detail = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
            switch status {
            case 401, 403: throw AIError(message: "API key 不对或没有权限（\(status)）：\(detail)")
            case 404: throw AIError(message: "找不到接口或模型（404），检查接口地址和模型名：\(detail)")
            case 429: throw AIError(message: "请求太频繁或额度用完了（429）：\(detail)")
            default: throw AIError(message: "接口返回 \(status)：\(detail)")
            }
        }
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError(message: "接口返回的格式看不懂：" + (String(data: data.prefix(300), encoding: .utf8) ?? ""))
        }
        return content
    }

    private func parse(_ content: String, ids: Set<String>) throws -> [String: AINote] {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"),
              let data = String(content[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else {
            throw AIError(message: "AI 没按要求返回 JSON：" + String(content.prefix(200)))
        }
        func text(_ v: Any?) -> String? {
            guard let s = v as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t == "null" ? nil : t
        }
        var notes = [String: AINote]()
        for item in items {
            guard let id = item["id"] as? String, ids.contains(id), let what = text(item["what"]) else { continue }
            notes[id] = AINote(what: what, owner: text(item["owner"]), group: text(item["group"]), advice: text(item["advice"]),
                               reason: text(item["reason"]), model: config.model, date: Date())
        }
        return notes
    }
}
