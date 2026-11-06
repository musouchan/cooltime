import Foundation

/// OpenCode V2's documented loopback API; Console credentials remain with OpenCode.
public enum OpenCodeGoUsage {
    private struct Response: Decodable {
        struct Info: Decodable {
            struct Workspace: Decodable { let id: String }
            struct Meter: Decodable { let percent: Double; let limited: Bool; let resetsAt: Double }
            struct Go: Decodable { let rolling: Meter; let weekly: Meter; let monthly: Meter }
            let workspace: Workspace
            let go: Go?
        }
        let data: Info?
    }

    public static func configuration(from input: String) throws -> (url: String, workspace: String, authorization: String) {
        let fields = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 3, !fields[0].isEmpty, fields[0].utf8.allSatisfy({ (48...57).contains($0) }),
              let port = Int(fields[0]), (1024...65535).contains(port),
              !fields[1].isEmpty, fields[1].utf8.count <= 256,
              fields[1].utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
              !fields[2].isEmpty, fields[2].utf8.count <= 4096,
              fields[2].utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ParseError.unsupported("ポート番号|ConsoleワークスペースID|ローカルサーバーパスワード の形式で入力してください")
        }
        let authorization = "Basic " + Data("opencode:\(fields[2])".utf8).base64EncodedString()
        return ("http://127.0.0.1:\(port)/api/experimental/usage/limits", fields[1], authorization)
    }

    public static func parse(_ data: Data, workspace: String, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 2_000_000, let response = try? JSONDecoder().decode(Response.self, from: data),
              let info = response.data, info.workspace.id == workspace, let go = info.go else {
            throw ParseError.unsupported("OpenCode Goの利用枠を取得できません。V2の接続先・契約・ワークスペースを確認してください")
        }
        let meters = [("Go ローリング枠", go.rolling), ("Go 週枠", go.weekly), ("Go 月枠", go.monthly)]
        let windows = try meters.map { label, meter -> UsageWindow in
            guard (0...100).contains(meter.percent),
                  (0...253_402_300_799_000).contains(meter.resetsAt) else {
                throw ParseError.unsupported("OpenCode Goの使用率またはリセット時刻が不正です")
            }
            let reset = Date(timeIntervalSince1970: meter.resetsAt / 1000)
            // Past reset times can accompany stale server data. Never fabricate a new window.
            guard reset > fetchedAt else {
                throw ParseError.unsupported("OpenCode Goの利用枠が古いため、公式アプリを更新して再取得してください")
            }
            // Preserve a rate-limited status even when the rounded percentage is below 100.
            return UsageWindow(label: label + (meter.limited ? "（制限中）" : ""), usedPercent: meter.percent,
                               resetsAt: reset, isLimited: meter.limited)
        }
        return Snapshot(windows: windows, fetchedAt: fetchedAt)
    }
}
