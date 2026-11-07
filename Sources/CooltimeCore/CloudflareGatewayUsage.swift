import Foundation

/// Account-wide AI Gateway Unified Billing usage, which can include Workers AI.
public enum CloudflareGatewayUsage {
    public struct Configuration: Sendable {
        let accountID: String
        public let token: String
    }

    private struct Response: Decodable {
        struct Result: Decodable {
            struct Bucket: Decodable {
                let start_time: Int64
                let end_time: Int64
                let aggregated_value: Double
            }
            let history: [Bucket]
        }
        struct ResultInfo: Decodable { let has_more: Bool? }
        let success: Bool
        let result: Result
        let result_info: ResultInfo?
    }

    public static func configuration(from value: String) throws -> Configuration {
        let fields = value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 2,
              fields[0].range(of: #"\A[0-9a-fA-F]{32}\z"#, options: .regularExpression) != nil,
              !fields[1].isEmpty, fields[1].utf8.count <= 4096,
              fields[1].utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ParseError.unsupported("Cloudflare account ID|AI Gateway ReadのAPIトークン の形式で入力してください")
        }
        return Configuration(accountID: fields[0], token: fields[1])
    }

    public static func url(config: Configuration, period: DailyUsagePeriod) -> String {
        var components = URLComponents(string: "https://api.cloudflare.com/client/v4/accounts/\(config.accountID)/ai-gateway/billing/usage-history")!
        components.queryItems = [URLQueryItem(name: "value_grouping_window", value: "day"),
                                 URLQueryItem(name: "start_time", value: String(milliseconds(period.start))),
                                 URLQueryItem(name: "end_time", value: String(milliseconds(period.end)))]
        return components.string!
    }

    public static func parse(_ data: Data, period: DailyUsagePeriod, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 100_000,
              let response = try? JSONDecoder().decode(Response.self, from: data), response.success,
              response.result_info?.has_more != true, response.result.history.count <= 7 else { throw invalid() }
        let start = milliseconds(period.start)
        let end = milliseconds(period.end)
        let day: Int64 = 86_400_000
        var seen = Set<Int64>()
        var total = 0.0
        for bucket in response.result.history {
            guard (start..<end).contains(bucket.start_time), (bucket.start_time - start) % day == 0,
                  bucket.end_time == bucket.start_time + day || bucket.end_time == bucket.start_time + day - 1,
                  seen.insert(bucket.start_time).inserted,
                  (0...9_007_199_254_740_991).contains(bucket.aggregated_value) else { throw invalid() }
            total += bucket.aggregated_value
        }
        guard total <= 9_007_199_254_740_991 else { throw invalid() }
        return Snapshot(windows: [UsageWindow(label: "AI Gateway利用額（\(period.label)）",
                                             reportedAmount: total, reportedUnit: "USD")], fetchedAt: fetchedAt)
    }

    private static func milliseconds(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

    private static func invalid() -> ParseError {
        .unsupported("Cloudflare AI Gatewayの利用額を確認できません")
    }
}
