import Foundation
import Security

/// Where to send recognition requests: any OpenAI-compatible chat completions endpoint.
struct AIConfig: Codable, Equatable {
    var baseURL = ""
    var model = ""
    /// Words replaced with *** before anything is sent, e.g. the user's real name.
    var blockedWords: [String]?

    struct Preset {
        let id: String
        let name: String
        let baseURL: String
        let model: String
    }

    static var presets: [Preset] {
        [
            Preset(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini"),
            Preset(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat"),
            Preset(id: "qwen", name: L("Qwen (Alibaba Cloud)"), baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus"),
            Preset(id: "kimi", name: "Kimi", baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k"),
            Preset(id: "zhipu", name: L("Zhipu GLM"), baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash"),
            Preset(id: "ollama", name: L("Ollama on this Mac"), baseURL: "http://localhost:11434/v1", model: "qwen2.5"),
        ]
    }

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
    private static let sensitive = #"(?i)简历|身份证|证件|护照|户口|学籍|学历|学位|毕业证|成绩|体检|病历|合同|协议|银行|流水|工资|社保|公积金|税|发票|密码|口令|私钥|密钥|凭证|证书|"#
        + #"履歴書|パスポート|免許証|保険証|マイナンバー|契約|請求書|給与|源泉|銀行|口座|診断|パスワード|証明書|"#
        + #"이력서|여권|주민등록|면허증|계약|청구서|급여|은행|계좌|진단|비밀번호|인증서|"#
        + #"\bresume\b|\bcv\b|passport|\bid[-_ ]?card|driver'?s?[-_ ]?licen[cs]e|contract|agreement|invoice|payslip|salary|"#
        + #"bank|statement|\btax|medical|diploma|transcript|api[-_ ]?key|token|secret|passw|credential|private|"#
        + #"\.pem$|\.p12$|\.key$|id_rsa|id_ed25519"#

    static func isSensitive(_ name: String) -> Bool {
        name.range(of: sensitive, options: .regularExpression) != nil
    }

    /// Masks long digit runs (phone and ID numbers) and the user's blocked words.
    static func clean(_ text: String, blocked: [String]) -> String {
        var s = text.replacingOccurrences(of: #"\d{7,}"#, with: "<digits>", options: .regularExpression)
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
        add[kSecAttrLabel as String] = "MacTidy AI API key"
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// What the AI made of one shelf or one item.
struct AINote: Codable {
    var what: String
    var owner: String?
    /// Finer grouping for personal files, e.g. work documents or study material.
    var group: String?
    /// An `AIAdvice` raw value.
    var advice: String?
    var reason: String?
    var model: String
    var date: Date

    var suggestion: AIAdvice? { advice.flatMap(AIAdvice.init(answer:)) }
}

enum AIAdvice: String {
    case keep, freeze, delete

    /// Accepts the codes the prompt asks for, and the Chinese words version 0.2 stored.
    init?(answer: String) {
        switch answer.lowercased() {
        case "keep", "保留": self = .keep
        case "freeze", "冷藏": self = .freeze
        case "delete", "可以删": self = .delete
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .keep: return L("Suggest keeping")
        case .freeze: return L("Suggest freezing")
        case .delete: return L("Suggest deleting")
        }
    }
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

    private static func instructions(language: String) -> String {
        """
        You are a macOS expert helping the user tidy up a Mac. It may have been moved over from older Macs with Migration Assistant \
        one or more times, and has piled up many things of unclear origin.
        The user gives you a list of items. Each has only a name, paths and metadata, never file contents. For each item, decide:
        - owner: which app, developer or tool left it behind; "the user" for the user's own files; null if you can't tell.
        - what: what it is for, in one or two concrete sentences; don't repeat the path.
        - group: only for items in the "\(Category.personal.name)" category, a finer group such as work documents, study material, \
        design assets, photos and videos, installers, code projects, backups, temporary files, games or music; null otherwise.
        - advice: one of keep, freeze, delete. Choose keep or freeze for things in use, important or uncertain; choose delete only \
        for clear uninstall leftovers, caches and outdated installers.
        - reason: one sentence explaining the advice.
        Infer only from what is given. If you aren't sure, say so; don't make things up.
        Write owner, what, group and reason in \(language). Keep advice as the English code.
        Output only JSON, nothing else: {"items":[{"id":"…","owner":"…","what":"…","group":null,"advice":"keep","reason":"…"}]}
        """
    }

    func recognise(_ subjects: [AISubject]) async throws -> [String: AINote] {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let payload = String(data: try enc.encode(subjects), encoding: .utf8) ?? "[]"
        let content = try await chat([
            ["role": "system", "content": AIClient.instructions(language: AppLanguage.englishName)],
            ["role": "user", "content": "Identify these items:\n" + payload],
        ])
        return try parse(content, ids: Set(subjects.map(\.id)))
    }

    /// A tiny request to check the address, model and key.
    func test() async throws -> String {
        try await chat([["role": "user", "content": "Reply with just the word OK."]], maxTokens: 10)
    }

    private func chat(_ messages: [[String: String]], maxTokens: Int? = nil) async throws -> String {
        let base = config.baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base.hasSuffix("/chat/completions") ? base : base + "/chat/completions") else {
            throw AIError(message: L("The endpoint address isn't valid"))
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
            if detail.range(of: #"(?i)ip.{0,20}(denied|not allowed|whitelist|restrict)"#, options: .regularExpression) != nil {
                throw AIError(message: L("This API key only accepts certain IP addresses, and this network's public IP isn't one of them (\(status)). Remove the IP restriction in the provider's console, or add your public IP to the allow list; with a proxy on, the public IP may be the proxy's. Original message: \(detail)"))
            }
            switch status {
            case 401, 403: throw AIError(message: L("The API key is wrong or lacks permission (\(status)): \(detail)"))
            case 404: throw AIError(message: L("Endpoint or model not found (404); check the address and model name: \(detail)"))
            case 429: throw AIError(message: L("Too many requests, or the quota is used up (429): \(detail)"))
            default: throw AIError(message: L("The endpoint returned \(status): \(detail)"))
            }
        }
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError(message: L("Couldn't understand the endpoint's reply: \(String(data: data.prefix(300), encoding: .utf8) ?? "")"))
        }
        return content
    }

    private func parse(_ content: String, ids: Set<String>) throws -> [String: AINote] {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"),
              let data = String(content[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else {
            throw AIError(message: L("The AI didn't reply with the requested JSON: \(String(content.prefix(200)))"))
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
