import Foundation

struct CommandUsage {
    var last: Date
    var count: Int
}

/// Parses zsh extended history (`: <epoch>:<duration>;<command>`) into per-command last-use times.
final class ShellHistory {
    private(set) var usage: [String: CommandUsage] = [:]
    private(set) var earliest: Date?
    private var aliases: [String: String] = [:]

    private static let wrappers: Set<String> = ["sudo", "time", "nohup", "command", "exec", "builtin", "noglob", "env", "xargs", "watch", "caffeinate"]

    init(historyFiles: [String], rcFiles: [String]) {
        rcFiles.forEach(loadAliases)
        historyFiles.forEach(load)
    }

    func lastUse(of names: [String]) -> CommandUsage? {
        names.compactMap { usage[$0] }.max { $0.last < $1.last }
    }

    private func loadAliases(_ path: String) {
        guard let text = readText(path) else { return }
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("alias "), let eq = t.firstIndex(of: "=") else { continue }
            let name = t[t.index(t.startIndex, offsetBy: 6)..<eq].trimmingCharacters(in: .whitespaces)
            let value = t[t.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            if let first = value.split(separator: " ").first { aliases[name] = String(first) }
        }
    }

    private func load(_ path: String) {
        guard let data = fm.contents(atPath: path) else { return }
        // zsh "metafies" bytes >= 0x80 as 0x83 followed by byte ^ 0x20.
        var bytes = [UInt8]()
        bytes.reserveCapacity(data.count)
        var meta = false
        for b in data {
            if meta { bytes.append(b ^ 0x20); meta = false }
            else if b == 0x83 { meta = true }
            else { bytes.append(b) }
        }
        let text = String(decoding: bytes, as: UTF8.self)

        var date: Date?
        var command = ""
        func flush() {
            if let date, !command.isEmpty { record(command, at: date) }
            command = ""
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(": "), let semi = line.firstIndex(of: ";"),
               let ts = line[line.index(line.startIndex, offsetBy: 2)..<semi].split(separator: ":").first.flatMap({ Double($0) }) {
                flush()
                date = Date(timeIntervalSince1970: ts)
                command = String(line[line.index(after: semi)...])
            } else if !command.isEmpty {
                command += "\n" + line
            }
        }
        flush()
    }

    private func record(_ command: String, at date: Date) {
        if earliest == nil || date < earliest! { earliest = date }
        let normalized = command.replacingOccurrences(of: "&&", with: ";").replacingOccurrences(of: "||", with: ";")
        for segment in normalized.split(whereSeparator: { "|;&\n(`".contains($0) }) {
            var tokens = segment.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)[...]
            while let t = tokens.first,
                  t.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil
                    || ShellHistory.wrappers.contains(t) || t.hasPrefix("-") {
                tokens = tokens.dropFirst()
            }
            guard var name = tokens.first else { continue }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "'\"{}$\\"))
            if name.contains("/") { name = (name as NSString).lastPathComponent }
            guard !name.isEmpty, name.count <= 64,
                  name.range(of: #"^[A-Za-z0-9._+-]+$"#, options: .regularExpression) != nil else { continue }
            bump(name, date)
            if let expanded = aliases[name], expanded != name { bump(expanded, date) }
        }
    }

    private func bump(_ name: String, _ date: Date) {
        if var u = usage[name] {
            u.count += 1
            if date > u.last { u.last = date }
            usage[name] = u
        } else {
            usage[name] = CommandUsage(last: date, count: 1)
        }
    }
}
