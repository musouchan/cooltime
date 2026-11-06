import Foundation

/// Enterprise organization Inference Providers report, not the shared compute balance.
public enum HuggingFaceUsage {
    private struct Period: Decodable {
        struct Row: Decodable {
            let user: String?
            let model: String?
            let provider: String
            let requestCount: Double
            let costCents: Double
        }
        let period: String
        let usage: [Row]
    }

    public static func configuration(from input: String) throws -> (organization: String, token: String) {
        let fields = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 2, !fields[0].isEmpty, fields[0].utf8.count <= 128,
              fields[0].utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
              !fields[1].isEmpty, fields[1].utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ParseError.unsupported("組織slug|billing読取トークン の形式で入力してください")
        }
        return (fields[0], fields[1])
    }

    public static func url(organization: String, period: DailyUsagePeriod) -> String {
        var parts = URLComponents(string: "https://huggingface.co")!
        parts.path = "/api/organizations/\(organization)/billing/usage/inference"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        parts.queryItems = [URLQueryItem(name: "startDate", value: iso.string(from: period.start)),
                            URLQueryItem(name: "endDate", value: iso.string(from: period.end.addingTimeInterval(-0.001))),
                            URLQueryItem(name: "limit", value: "31")]
        return parts.string!
    }

    public static func parse(_ data: Data, linkHeader: String?, period: DailyUsagePeriod, fetchedAt: Date) throws -> Snapshot {
        // Seven days fit within the official 31-day page. Do not follow unexpected pagination URLs.
        guard linkHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              data.count <= 8_000_000, let report = try? JSONDecoder().decode([Period].self, from: data),
              !report.isEmpty, report.count <= 7 else { throw invalid() }
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var days = Set<Date>()
        var cents = 0.0, requests = 0.0
        let maximum = 9_007_199_254_740_991.0
        for bucket in report {
            guard let day = iso.date(from: bucket.period) ?? fractional.date(from: bucket.period),
                  day >= period.start, day < period.end,
                  day.timeIntervalSince(period.start).truncatingRemainder(dividingBy: 86_400) == 0,
                  days.insert(day).inserted, bucket.usage.count <= 100_000 else { throw invalid() }
            var grains = Set<[String?]>()
            for row in bucket.usage {
                guard !row.provider.isEmpty, grains.insert([row.user, row.model, row.provider]).inserted,
                      (0...maximum - cents).contains(row.costCents),
                      (0...maximum - requests).contains(row.requestCount),
                      row.requestCount.rounded(.towardZero) == row.requestCount else { throw invalid() }
                cents += row.costCents
                requests += row.requestCount
            }
        }
        return Snapshot(windows: [
            UsageWindow(label: "推論費用（行別丸め）・\(period.label)", reportedAmount: cents, reportedUnit: "cents"),
            UsageWindow(label: "推論リクエスト・\(period.label)", reportedAmount: requests, reportedUnit: "回")
        ], fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Hugging Faceの完全な日次実績を確認できません。期間・ページ・金額の形式を確認してください")
    }
}
