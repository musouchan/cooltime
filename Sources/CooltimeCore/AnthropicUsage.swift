import Foundation

public enum AnthropicUsage {
    public static let apiVersion = "2026-10-21"
    public static let betaHeader = "analytics-usage-cost-2026-08-24"

    public static func costsURL(now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: parts) ?? now
        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/analytics/cost")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: timestamp(start)),
            URLQueryItem(name: "ending_at", value: timestamp(now))
        ]
        return components.url!.absoluteString
    }

    public static func parse(_ data: Data) throws -> Snapshot {
        let root = try object(data)
        guard root["has_more"] as? Bool != true,
              let refreshedText = root["data_refreshed_at"] as? String,
              let refreshedAt = parseTimestamp(refreshedText),
              let rows = root["data"] as? [[String: Any]] else {
            throw ParseError.unsupported("当月Analyticsの完全な集計がありません")
        }
        var spentUSD = 0.0
        for row in rows {
            guard let cost = row["cost"] as? [String: Any],
                  let amountText = cost["amount"] as? String,
                  let fractionalCents = Double(amountText), fractionalCents.isFinite, fractionalCents >= 0,
                  cost["currency"] as? String == "USD" else {
                throw ParseError.invalid("Cost APIの金額または通貨を確認できません")
            }
            // The API reports amount in fractional cents (minor units).
            spentUSD += fractionalCents / 100
        }
        return Snapshot(windows: [
            UsageWindow(label: "当月コスト実績（反映遅延あり）",
                        reportedAmount: spentUSD, reportedUnit: "USD")
        ], fetchedAt: refreshedAt)
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalid("JSON object がありません")
        }
        return value
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
