import Foundation

/// Claude Code の settings.json に、ステータスラインの記録スクリプトを足す（または外す）。
/// 本人が内容を見て同意したときだけ書く前提。すでにあるステータスラインは壊さず、
/// 記録したうえで、そのまま表示も続ける形にする。
public enum StatuslineConfig {
    public struct Change: Equatable {
        public let newData: Data
        public let before: String
        public let after: String
        public let alreadySet: Bool
    }

    static func quote(_ path: String) -> String { "\"" + path.replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    static func shSingle(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func loadRoot(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.unsupported("settings.json を読み取れないため、変更しません")
        }
        return obj
    }

    static func serialize(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    public static func isSet(_ data: Data?, scriptPath: String) -> Bool {
        guard let root = try? loadRoot(data), let sl = root["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String else { return false }
        return cmd.hasPrefix(quote(scriptPath))
    }

    public static func plan(existing: Data?, scriptPath: String) throws -> Change {
        var root = try loadRoot(existing)
        let ours = quote(scriptPath)
        var before = "（未設定）"
        var command = ours
        var statusLine: [String: Any] = [:]

        if let current = root["statusLine"] {
            guard let sl = current as? [String: Any], (sl["type"] as? String) == "command",
                  let cmd = sl["command"] as? String else {
                throw ParseError.unsupported("既存のステータスラインの形式に対応していないため、変更しません")
            }
            before = cmd
            if cmd.hasPrefix(ours) {
                return Change(newData: existing ?? Data(), before: cmd, after: cmd, alreadySet: true)
            }
            command = ours + " " + shSingle(cmd)
            statusLine = sl
        }
        statusLine["type"] = "command"
        statusLine["command"] = command
        root["statusLine"] = statusLine
        return Change(newData: try serialize(root), before: before, after: command, alreadySet: false)
    }

    /// 元に戻す。Cooltime が足した形でなければ nil（触らない）。
    public static func revert(existing: Data, scriptPath: String) throws -> Data? {
        var root = try loadRoot(existing)
        let ours = quote(scriptPath)
        guard var sl = root["statusLine"] as? [String: Any], let cmd = sl["command"] as? String,
              cmd.hasPrefix(ours) else { return nil }
        let rest = String(cmd.dropFirst(ours.count)).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty {
            root.removeValue(forKey: "statusLine")
        } else if rest.count >= 2, rest.hasPrefix("'"), rest.hasSuffix("'") {
            sl["command"] = String(rest.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
            root["statusLine"] = sl
        } else {
            return nil
        }
        return try serialize(root)
    }
}
