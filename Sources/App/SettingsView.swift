import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var language = LanguageSetting.chosen
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var key = ""
    @State private var blocked = ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("Language", selection: $language) {
                    Text("Same as System").tag("")
                    Divider()
                    ForEach(LanguageSetting.options, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                }
                .onChange(of: language) { LanguageSetting.choose(language) }
                if language != LanguageSetting.atLaunch {
                    HStack {
                        Text("Takes effect after MacTidy restarts; the Mac is then scanned again in the new language.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { LanguageSetting.relaunch() }
                    }
                }
            } header: {
                Text("General")
            }

            SwiftUI.Section {
                Picker("Service", selection: Binding(get: { presetID }, set: applyPreset)) {
                    ForEach(AIConfig.presets, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                    Divider()
                    Text("Custom").tag("")
                }
                TextField("Endpoint", text: $baseURL, prompt: Text(verbatim: "https://…/v1"))
                TextField("Model", text: $modelName, prompt: Text("Model name"))
                SecureField("API key", text: $key, prompt: isLocalURL ? Text("Usually not needed for a local service") : Text(verbatim: "sk-…"))
                TextField("Never send", text: $blocked, prompt: Text("e.g. your name; separate with commas"))
            } header: {
                Text("AI Recognition")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Works with any OpenAI-compatible endpoint (/chat/completions). The API key is stored in your keychain.")
                    Text("Only names, paths (with your home folder written as ~), kinds, sizes and dates are sent. File contents are never read.")
                    Text("Items named like ID documents, contracts or keys aren't sent; numbers of 7 or more digits (phone and ID numbers) are masked; words under Never send become ***.")
                    if insecure {
                        Text("This address isn't https, so the API key travels in plain text.").foregroundStyle(.primary)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(!dirty)
                Button("Test Connection") { test() }.disabled(testing || baseURL.isEmpty || modelName.isEmpty)
                if testing { ProgressView().controlSize(.small) }
                if let r = testResult {
                    Label(r.text, systemImage: r.ok ? "checkmark.circle" : "xmark.circle")
                        .font(.caption).lineLimit(3).foregroundStyle(r.ok ? .primary : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .tint(.primary)
        .onAppear(perform: loadFields)
    }

    private var current: AIConfig {
        let words = blocked.split(whereSeparator: { ",，、;；".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return AIConfig(baseURL: baseURL.trimmingCharacters(in: .whitespaces), model: modelName.trimmingCharacters(in: .whitespaces),
                        blockedWords: words.isEmpty ? nil : words)
    }

    private var presetID: String {
        AIConfig.presets.first { $0.baseURL == current.baseURL }?.id ?? ""
    }

    private var isLocalURL: Bool { current.isLocal }
    private var insecure: Bool { baseURL.lowercased().hasPrefix("http://") && !isLocalURL }
    private var dirty: Bool { current != model.aiConfig || key != (AIKey.read(for: current.baseURL) ?? "") }

    private func loadFields() {
        baseURL = model.aiConfig.baseURL
        modelName = model.aiConfig.model
        blocked = (model.aiConfig.blockedWords ?? []).joined(separator: ", ")
        key = AIKey.read(for: baseURL) ?? ""
    }

    private func applyPreset(_ id: String) {
        testResult = nil
        guard let p = AIConfig.presets.first(where: { $0.id == id }) else { baseURL = ""; modelName = ""; key = ""; return }
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
                testResult = (true, L("Connected: \(String(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20)))"))
            } catch {
                testResult = (false, error.localizedDescription)
            }
            testing = false
        }
    }
}

/// The app's own language, kept apart from the system's in this app's `AppleLanguages` default.
enum LanguageSetting {
    /// Each language under its own name, the way language menus show them.
    static let options = [("en", "English"), ("zh-Hans", "简体中文"), ("ja", "日本語"), ("ko", "한국어")]
        .map { (code: $0.0, name: $0.1) }

    /// The language picked in MacTidy, or "" to follow the system.
    static var chosen: String {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        return (domain?["AppleLanguages"] as? [String])?.first ?? ""
    }

    /// What was chosen when this run started; changes only apply after a restart.
    static let atLaunch = chosen

    static func choose(_ code: String) {
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
