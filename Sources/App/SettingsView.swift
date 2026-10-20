import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var key = ""
    @State private var blocked = ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("服务", selection: Binding(get: { presetName }, set: applyPreset)) {
                    ForEach(AIConfig.presets, id: \.name) { Text($0.name).tag($0.name) }
                    Divider()
                    Text("自定义").tag("自定义")
                }
                TextField("接口地址", text: $baseURL, prompt: Text("https://…/v1"))
                TextField("模型", text: $modelName, prompt: Text("模型名"))
                SecureField("API key", text: $key, prompt: Text(isLocalURL ? "本机服务一般不用填" : "sk-…"))
                TextField("不发送的词", text: $blocked, prompt: Text("比如你的名字，用逗号隔开"))
            } header: {
                Text("AI 识别")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("支持所有兼容 OpenAI 格式（/chat/completions）的接口。API key 存在钥匙串里。")
                    Text("只会发送名称、路径（主目录写成 ~）、类型、大小和日期，不读取文件内容。")
                    Text("名字像证件、合同、密钥的条目不发送；7 位以上的数字（手机号、证件号）会打码；「不发送的词」会替换成 ***。")
                    if insecure {
                        Text("这个地址不是 https，API key 会以明文传输。").foregroundStyle(.primary)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(!dirty)
                Button("测试连接") { test() }.disabled(testing || baseURL.isEmpty || modelName.isEmpty)
                if testing { ProgressView().controlSize(.small) }
                if let r = testResult {
                    Label(r.text, systemImage: r.ok ? "checkmark.circle" : "xmark.circle")
                        .font(.caption).lineLimit(3).foregroundStyle(r.ok ? .primary : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .tint(.primary)
        .onAppear(perform: loadFields)
    }

    private var current: AIConfig {
        let words = blocked.split(whereSeparator: { ",，、".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return AIConfig(baseURL: baseURL.trimmingCharacters(in: .whitespaces), model: modelName.trimmingCharacters(in: .whitespaces),
                        blockedWords: words.isEmpty ? nil : words)
    }

    private var presetName: String {
        AIConfig.presets.first { $0.baseURL == current.baseURL }?.name ?? "自定义"
    }

    private var isLocalURL: Bool { current.isLocal }
    private var insecure: Bool { baseURL.lowercased().hasPrefix("http://") && !isLocalURL }
    private var dirty: Bool { current != model.aiConfig || key != (AIKey.read(for: current.baseURL) ?? "") }

    private func loadFields() {
        baseURL = model.aiConfig.baseURL
        modelName = model.aiConfig.model
        blocked = (model.aiConfig.blockedWords ?? []).joined(separator: "，")
        key = AIKey.read(for: baseURL) ?? ""
    }

    private func applyPreset(_ name: String) {
        testResult = nil
        guard let p = AIConfig.presets.first(where: { $0.name == name }) else { baseURL = ""; modelName = ""; key = ""; return }
        baseURL = p.baseURL
        modelName = p.model
        key = AIKey.read(for: p.baseURL) ?? ""
    }

    private func save() {
        let c = current
        c.save()
        AIKey.write(key.trimmingCharacters(in: .whitespacesAndNewlines), for: c.baseURL)
        model.aiConfig = c
        model.aiError = nil
    }

    private func test() {
        testing = true
        testResult = nil
        let client = AIClient(config: current, key: key.trimmingCharacters(in: .whitespacesAndNewlines))
        Task {
            do {
                let reply = try await client.test()
                testResult = (true, "连接成功：\(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))")
            } catch {
                testResult = (false, error.localizedDescription)
            }
            testing = false
        }
    }
}
