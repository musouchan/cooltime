import Foundation

/// Read-only monthly cost reporting through xAI's documented Management API.
public enum XAIUsage {
    public static func teamID(from validationData: Data) throws -> String {
        let root = try json(validationData)
        guard root["scope"] as? String == "SCOPE_TEAM",
              let scopeID = root["scopeId"] as? String, !scopeID.isEmpty else {
            throw ParseError.unsupported("Team scope の xAI Management API key が必要です")
        }
        return scopeID
    }

    public static func usageURL(teamID: String) -> String {
        let encoded = teamID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? teamID
        return "https://management-api.x.ai/v1/billing/teams/\(encoded)/usage"
    }

    /// Request the current UTC calendar month. The API uses timezone-aware local
    /// boundaries; Etc/GMT fixes the range to UTC regardless of the Mac timezone.
    public static func usageRequestBody(now: Date) throws -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let monthStart = calendar.date(from: components) else {
            throw ParseError.invalid("当月の開始日を作れません")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let request: [String: Any] = [
            "analyticsRequest": [
                "timeRange": [
                    "startTime": formatter.string(from: monthStart),
                    "endTime": formatter.string(from: now),
                    "timezone": "Etc/GMT"
                ],
                "timeUnit": "TIME_UNIT_DAY",
                "values": [["name": "usd", "aggregation": "AGGREGATION_SUM"]],
                "groupBy": ["description"],
                "filters": []
            ]
        ]
        return try JSONSerialization.data(withJSONObject: request)
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        guard let complete = root["limitReached"] as? Bool, !complete,
              let series = root["timeSeries"] as? [[String: Any]] else {
            throw ParseError.unsupported("当月の完全な使用量レポートがありません")
        }
        var totalUSD = 0.0
        for line in series {
            guard let points = line["dataPoints"] as? [[String: Any]] else {
                throw ParseError.invalid("timeSeries.dataPoints がありません")
            }
            for point in points {
                guard let values = point["values"] as? [Any],
                      let amount = number(values.first), amount.isFinite, amount >= 0 else {
                    throw ParseError.invalid("使用量のUSD値がありません")
                }
                totalUSD += amount
            }
        }
        guard totalUSD.isFinite else { throw ParseError.invalid("USD合計が不正です") }
        return Snapshot(windows: [
            UsageWindow(label: "当月APIコスト実績",
                        reportedAmount: totalUSD, reportedUnit: "USD")
        ], fetchedAt: fetchedAt)
    }
}
