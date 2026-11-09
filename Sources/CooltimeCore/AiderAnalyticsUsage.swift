import Foundation
import CoreFoundation

/// Reads user-selected Aider analytics JSONL. Only message_send numeric usage is retained.
public enum AiderAnalyticsUsage {
    private static let maximumBytes = 8 * 1_024 * 1_024

    public static func read(path: String) throws -> Snapshot {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), !path.contains("\0"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { throw invalid() }
        return try parse(data, fetchedAt: Date())
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else { throw invalid() }
        var prompt = 0.0, completion = 0.0, cost = 0.0
        var count = 0
        for line in text.split(whereSeparator: \.isNewline) {
            guard let bytes = String(line).data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw invalid() }
            guard record["event"] as? String == "message_send" else { continue }
            guard let properties = record["properties"] as? [String: Any],
                  let inTokens = number(properties["prompt_tokens"]),
                  let outTokens = number(properties["completion_tokens"]),
                  let eventCost = number(properties["cost"]),
                  let timestamp = number(record["time"]), timestamp > 0 else { throw invalid() }
            prompt += inTokens
            completion += outTokens
            cost += eventCost
            count += 1
            guard prompt.isFinite, completion.isFinite, cost.isFinite else { throw invalid() }
        }
        guard count > 0 else { throw invalid() }
        return Snapshot(windows: [
            UsageWindow(label: "Aider入力（ログ全期間）", reportedAmount: prompt, reportedUnit: "tokens"),
            UsageWindow(label: "Aider出力（ログ全期間）", reportedAmount: completion, reportedUnit: "tokens"),
            UsageWindow(label: "Aider推定費用（ログ全期間）", reportedAmount: cost, reportedUnit: "USD")
        ], fetchedAt: fetchedAt)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let v = n.doubleValue
        return v.isFinite && v >= 0 && v <= 9_007_199_254_740_991 ? v : nil
    }

    private static func invalid() -> ParseError {
        .unsupported("Aiderの指定analyticsログから利用実績を確認できません")
    }
}
