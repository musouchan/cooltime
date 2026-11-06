import Foundation

/// OpenAI Platform の公式 Admin API から、強制中の組織月次支出上限と当月コストを読む。
/// Spend limit が未設定または enforcement=false の場合は残額を表示しない。
public enum OpenAIPlatformUsage {
    public static func costsURL(now: Date) -> String {
        let calendar = utcCalendar
        let components = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: components) ?? now
        let startTime = Int(start.timeIntervalSince1970)
        let endTime = Int(now.timeIntervalSince1970)
        return "https://api.openai.com/v1/organization/costs?start_time=\(startTime)&end_time=\(endTime)&bucket_width=1d&limit=31"
    }

    public static func parse(limitData: Data, costsData: Data, now: Date, fetchedAt: Date) throws -> Snapshot {
        let limitRoot = try object(limitData)
        guard let enforcement = limitRoot["enforcement"] as? Bool, enforcement,
              limitRoot["interval"] as? String == "month",
              let thresholdCents = numeric(limitRoot["threshold_amount"]),
              thresholdCents.isFinite, thresholdCents >= 0,
              let currency = limitRoot["currency"] as? String, !currency.isEmpty else {
            throw ParseError.unsupported("強制中の組織月次支出上限を確認できません")
        }
        let costsRoot = try object(costsData)
        guard costsRoot["has_more"] as? Bool != true,
              let buckets = costsRoot["data"] as? [[String: Any]] else {
            throw ParseError.unsupported("当月コストの全ページを読み取れません")
        }
        var spent = 0.0
        for bucket in buckets {
            guard let results = bucket["results"] as? [[String: Any]] else {
                throw ParseError.invalid("コスト明細がありません")
            }
            for result in results {
                guard let amount = result["amount"] as? [String: Any],
                      let value = numeric(amount["value"]), value.isFinite, value >= 0,
                      let unit = amount["currency"] as? String,
                      unit.caseInsensitiveCompare(currency) == .orderedSame else {
                    throw ParseError.invalid("コスト金額または通貨を確認できません")
                }
                spent += value
            }
        }
        let limit = thresholdCents / 100
        let remaining = max(0, limit - spent)
        let percent = limit == 0 ? 100 : spent / limit * 100
        return Snapshot(windows: [
            UsageWindow(label: "OpenAI 組織月次ハード上限", usedPercent: percent,
                        remainingCount: remaining, resetsAt: nextMonthStart(after: now))
        ], fetchedAt: fetchedAt)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func nextMonthStart(after date: Date) -> Date {
        let current = utcCalendar.dateComponents([.year, .month], from: date)
        let start = utcCalendar.date(from: current) ?? date
        return utcCalendar.date(byAdding: .month, value: 1, to: start) ?? date
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalid("JSON object がありません")
        }
        return value
    }

    private static func numeric(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }
}
