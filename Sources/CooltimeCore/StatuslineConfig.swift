import Foundation

/// Claude Code の settings.json に、Cooltime 用の設定を足す（または外す）。
/// - statusLine: ターミナル版の利用枠を記録するスクリプト。すでにあるものは壊さず、表示も続ける。
/// - Stop フック: 返事が終わったら、Cooltime に合図する（手元のファイルを更新するだけ）。
/// 本人が内容を見て同意したときだけ書く前提。
public enum StatuslineConfig {
    public struct Change: Equatable {
        public let newData: Data
        public let before: String
        public let after: String
        public let addsHook: Bool
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

    static func statuslineIsOurs(_ root: [String: Any], _ scriptPath: String) -> Bool {
        guard let sl = root["statusLine"] as? [String: Any], let cmd = sl["command"] as? String else { return false }
        return cmd.hasPrefix(quote(scriptPath))
    }

    static func hookIsSet(_ root: [String: Any], _ hookCommand: String) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any], let stop = hooks["Stop"] as? [[String: Any]] else { return false }
        return stop.contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String) == hookCommand }
        }
    }

    public static func isSet(_ data: Data?, scriptPath: String, hookCommand: String? = nil) -> Bool {
        guard let root = try? loadRoot(data) else { return false }
        return statuslineIsOurs(root, scriptPath) && (hookCommand.map { hookIsSet(root, $0) } ?? true)
    }

    public static func plan(existing: Data?, scriptPath: String, hookCommand: String? = nil) throws -> Change {
        var root = try loadRoot(existing)
        let ours = quote(scriptPath)
        var before = "（未設定）"
        var after = ours
        var changed = false

        if let current = root["statusLine"] {
            guard let sl = current as? [String: Any], (sl["type"] as? String) == "command",
                  let cmd = sl["command"] as? String else {
                throw ParseError.unsupported("既存のステータスラインの形式に対応していないため、変更しません")
            }
            before = cmd
            after = cmd
            if !cmd.hasPrefix(ours) {
                var updated = sl
                after = ours + " " + shSingle(cmd)
                updated["command"] = after
                root["statusLine"] = updated
                changed = true
            }
        } else {
            root["statusLine"] = ["type": "command", "command": ours]
            changed = true
        }

        var addsHook = false
        if let hookCommand, !hookIsSet(root, hookCommand) {
            if root["hooks"] != nil && !(root["hooks"] is [String: Any]) {
                throw ParseError.unsupported("既存のフックの形式に対応していないため、変更しません")
            }
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            if hooks["Stop"] != nil && !(hooks["Stop"] is [[String: Any]]) {
                throw ParseError.unsupported("既存のフックの形式に対応していないため、変更しません")
            }
            var stop = hooks["Stop"] as? [[String: Any]] ?? []
            stop.append(["hooks": [["type": "command", "command": hookCommand]]])
            hooks["Stop"] = stop
            root["hooks"] = hooks
            addsHook = true
            changed = true
        }

        return Change(newData: changed ? try serialize(root) : (existing ?? Data()),
                      before: before, after: after, addsHook: addsHook, alreadySet: !changed)
    }

    /// 元に戻す。Cooltime が足したものだけを外す。何も外すものが無ければ nil（触らない）。
    public static func revert(existing: Data, scriptPath: String, hookCommand: String? = nil) throws -> Data? {
        var root = try loadRoot(existing)
        let ours = quote(scriptPath)
        var changed = false

        if var sl = root["statusLine"] as? [String: Any], let cmd = sl["command"] as? String, cmd.hasPrefix(ours) {
            let rest = String(cmd.dropFirst(ours.count)).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                root.removeValue(forKey: "statusLine")
                changed = true
            } else if rest.count >= 2, rest.hasPrefix("'"), rest.hasSuffix("'") {
                sl["command"] = String(rest.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
                root["statusLine"] = sl
                changed = true
            }
        }

        if let hookCommand, hookIsSet(root, hookCommand),
           var hooks = root["hooks"] as? [String: Any], let stop = hooks["Stop"] as? [[String: Any]] {
            let kept = stop.compactMap { group -> [String: Any]? in
                var g = group
                let inner = (group["hooks"] as? [[String: Any]] ?? []).filter { ($0["command"] as? String) != hookCommand }
                if inner.isEmpty && group["hooks"] != nil { return nil }
                g["hooks"] = inner
                return g
            }
            changed = true
            if kept.isEmpty { hooks.removeValue(forKey: "Stop") } else { hooks["Stop"] = kept }
            if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        }
        return changed ? try serialize(root) : nil
    }
}
