import Foundation

public enum ThoughtSpotSpotterUsage {
    public struct Configuration: Sendable {
        public let url: String
        public let token: String
    }

    private struct Response: Decodable {
        struct Summary: Decodable {
            struct Pool: Decodable { let usage: Int64 }
            let pools: [Pool]
            let totalUsage: Int64?
            let totalRemaining: Int64?
            let hasUnlimitedPool: Bool
            let isAtLimit: Bool
        }
        let summary: Summary
    }

    public static func configuration(from input: String) throws -> Configuration {
        let fields = input.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.count == 2,
              fields[0].range(of: #"\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.thoughtspot\.cloud\z"#,
                              options: .regularExpression) != nil,
              !fields[1].isEmpty, fields[1].utf8.count <= 8192,
              fields[1].utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ParseError.unsupported("tenant.thoughtspot.cloud|本人のThoughtSpot APIトークン を入力してください")
        }
        return Configuration(url: "https://\(fields[0])/api/rest/2.0/ai/usage-data/user", token: fields[1])
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let maxExact: Int64 = 9_007_199_254_740_991
        guard data.count <= 1_000_000, let response = try? decoder.decode(Response.self, from: data) else { throw invalid() }
        let summary = response.summary
        guard !summary.pools.isEmpty else {
            throw ParseError.unsupported("ThoughtSpot Spotterで本人を計測する利用枠が設定されていません")
        }
        guard let usage = summary.totalUsage, (0...maxExact).contains(usage) else { throw invalid() }

        let remaining: Double?
        if summary.hasUnlimitedPool {
            guard !summary.isAtLimit else { throw invalid() }
            remaining = nil
        } else {
            guard let value = summary.totalRemaining, (0...maxExact).contains(value),
                  (value == 0) == summary.isAtLimit else { throw invalid() }
            remaining = Double(value)
        }
        let window = UsageWindow(label: "Spotter・本人の質問枠",
                                 remainingCount: remaining, reportedAmount: Double(usage), reportedUnit: "件使用",
                                 isLimited: summary.isAtLimit)
        return Snapshot(windows: [window], fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("ThoughtSpot Spotterの質問枠を確認できません")
    }
}
