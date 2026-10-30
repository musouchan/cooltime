import Foundation

/// Claude Code のステータスラインが書き出したファイルを読む。通信はしない。
/// 書き出しは scripts/statusline-tee.sh が行う（rate_limits の部分だけを保存する）。
public struct StatuslineSource: Sendable {
    public let fileURL: URL

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cooltime/claude-statusline.json")
    }

    public init(fileURL: URL = StatuslineSource.defaultURL) { self.fileURL = fileURL }

    public func read() throws -> SourceResult {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw SourceError.notAvailable("まだ読み込めていません。Claude Code で1回メッセージを送ると表示されます")
        }
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> SourceResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.unexpectedResponse("JSONではありません")
        }
        // 保存形式は rate_limits だけ、または Claude Code の入力そのまま、のどちらでも読める
        let limits = (root["rate_limits"] as? [String: Any]) ?? root
        var windows: [WindowStatus] = []
        for (key, name) in [("five_hour", "5時間枠"), ("seven_day", "週の枠")] {
            guard let w = limits[key] as? [String: Any],
                  let used = (w["used_percentage"] as? NSNumber)?.doubleValue,
                  let reset = (w["resets_at"] as? NSNumber)?.doubleValue else { continue }
            windows.append(WindowStatus(name: name, usedPercent: used,
                                        resetsAt: Date(timeIntervalSince1970: reset)))
        }
        if windows.isEmpty {
            // Pro／Max 以外、または最初の応答の前は項目がない。何も作らない。
            throw SourceError.notAvailable("利用枠の情報がありません（Pro／Max 契約で、最初の応答の後に出ます）")
        }
        return SourceResult(windows: windows)
    }
}
