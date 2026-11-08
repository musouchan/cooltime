import Foundation

/// Official, read-only Together billing usage report (Beta).
public enum TogetherBilling {
    public static func monthString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year!, parts.month!)
    }

    public static func usageURL(now: Date) -> String {
        var components = URLComponents(string: "https://api.together.ai/v1/billing/usage")!
        components.queryItems = [
            URLQueryItem(name: "month", value: monthString(now)),
            URLQueryItem(name: "granularity", value: "day"),
            URLQueryItem(name: "limit", value: "1000")
        ]
        return components.url!.absoluteString
    }

    public static func parse(_ data: Data, expectedMonth: String, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        guard root["object"] as? String == "list",
              root["billing_period"] as? String == expectedMonth,
              root["currency"] as? String == "USD",
              let rows = root["data"] as? [[String: Any]] else {
            throw ParseError.invalid("Billing Usageの月・通貨・明細を確認できません")
        }
        if let cursor = root["next_cursor"], !(cursor is NSNull), !(cursor as? String ?? "").isEmpty {
            throw ParseError.unsupported("Billing Usageが複数ページです。全ページ取得が必要です")
        }
        var totalUSD = 0.0
        for row in rows {
            guard let items = row["line_items"] as? [[String: Any]] else {
                throw ParseError.invalid("line_items がありません")
            }
            for item in items {
                guard let costText = item["cost"] as? String,
                      let cost = Double(costText), cost.isFinite, cost >= 0 else {
                    throw ParseError.invalid("line item cost が不正です")
                }
                totalUSD += cost
            }
        }
        guard totalUSD.isFinite else { throw ParseError.invalid("USD合計が不正です") }
        return Snapshot(windows: [
            UsageWindow(label: "当月APIコスト実績（前日まで）",
                        reportedAmount: totalUSD, reportedUnit: "USD")
        ], fetchedAt: fetchedAt)
    }
}
