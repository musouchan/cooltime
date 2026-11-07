import Foundation

/// Freepik/Magnific Business and Enterprise Analytics API: observed team consumption.
public enum MagnificTeamCredits {
    public static let url = "https://api.magnific.com/v1/analytics/team-credit-usage"

    private struct Response: Decodable {
        struct Bucket: Decodable {
            struct Consumption: Decodable {
                let tool_name: String
                let user_uses: Double
                let user_credits: Double
            }
            let date: String
            let consumptions: [Consumption]
        }
        let data: [Bucket]
    }

    public static func period(now: Date) -> DailyUsagePeriod {
        .previousSevenDays(now: now, lagHours: 6)
    }

    public static func requestBody(period: DailyUsagePeriod) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["granularity": "day", "start_date": period.firstDay,
                                                    "end_date": period.lastDay])
    }

    public static func parse(_ data: Data, period: DailyUsagePeriod, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 4_000_000, let response = try? JSONDecoder().decode(Response.self, from: data),
              response.data.count <= 7 else { throw invalid() }
        var dates = Set<String>()
        var credits = 0.0, uses = 0.0
        for bucket in response.data {
            guard bucket.date.count >= 10, period.contains(String(bucket.date.prefix(10))),
                  dates.insert(String(bucket.date.prefix(10))).inserted,
                  bucket.consumptions.count <= 10_000 else { throw invalid() }
            for entry in bucket.consumptions {
                guard !entry.tool_name.isEmpty, entry.tool_name.utf8.count <= 256,
                      entry.user_credits.isFinite, entry.user_uses.isFinite,
                      entry.user_credits >= 0, entry.user_uses >= 0,
                      entry.user_credits <= 9_007_199_254_740_991,
                      entry.user_uses <= 9_007_199_254_740_991 else { throw invalid() }
                // Separate tool_name rows can have identical values and must both be counted.
                credits += entry.user_credits
                uses += entry.user_uses
            }
        }
        guard credits.isFinite, uses.isFinite else { throw invalid() }
        return Snapshot(windows: [
            UsageWindow(label: "Magnificチーム・消費クレジット \(period.label)", reportedAmount: credits, reportedUnit: "credits"),
            UsageWindow(label: "Magnificチーム・利用回数 \(period.label)", reportedAmount: uses, reportedUnit: "uses")
        ], fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Magnific/Freepikチームの公式クレジット利用実績を確認できません")
    }
}
