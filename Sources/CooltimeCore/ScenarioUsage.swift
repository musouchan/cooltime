import Foundation

/// Scenario's official team limits response for the current billing period.
public enum ScenarioUsage {
    public struct Configuration {
        public let teamID: String
        public let apiKey: String
        public let apiSecret: String

        public var authorization: String {
            "Basic " + Data((apiKey + ":" + apiSecret).utf8).base64EncodedString()
        }
    }

    private struct Response: Decodable {
        struct Limits: Decodable { let creativeUnits: Double }
        struct Values: Decodable { let creativeUnits: Double }
        struct Period: Decodable { let start: String; let end: String }
        struct OneShot: Decodable {
            let amount: Double
            let remaining: Double
            let createdAt: String
            let expiration: String
            let updatedAt: String
        }

        let limits: Limits
        let oneShotCreativeUnits: [OneShot]
        let period: Period
        let plan: String
        let values: Values
    }

    public static func configuration(from input: String) throws -> Configuration {
        let parts = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              validID(parts[0]),
              validSecret(parts[1]),
              validSecret(parts[2]) else { throw invalid() }
        return Configuration(teamID: parts[0], apiKey: parts[1], apiSecret: parts[2])
    }

    public static func url(teamID: String) throws -> String {
        guard validID(teamID) else { throw invalid() }
        return "https://api.cloud.scenario.com/v1/teams/\(teamID)/limits"
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 2_000_000,
              let value = try? JSONDecoder().decode(Response.self, from: data),
              !value.plan.isEmpty, value.plan.utf8.count <= 128,
              validNumber(value.limits.creativeUnits),
              validNumber(value.values.creativeUnits),
              let start = date(value.period.start),
              let end = date(value.period.end),
              end > start,
              value.oneShotCreativeUnits.count <= 10_000 else { throw invalid() }

        var oneShotRemaining = 0.0
        for item in value.oneShotCreativeUnits {
            guard validNumber(item.amount), validNumber(item.remaining),
                  item.remaining <= item.amount,
                  let created = date(item.createdAt),
                  let expiration = date(item.expiration),
                  let updated = date(item.updatedAt),
                  expiration >= created, updated >= created else { throw invalid() }
            oneShotRemaining += item.remaining
            guard oneShotRemaining.isFinite,
                  oneShotRemaining <= 9_007_199_254_740_991 else { throw invalid() }
        }

        let limit = value.limits.creativeUnits
        let used = value.values.creativeUnits
        let remaining = max(0, limit - used)
        let percent = limit > 0 ? used / limit * 100 : nil
        let window = UsageWindow(label: "請求期間のプランCU",
                                 usedPercent: percent,
                                 remainingCount: remaining,
                                 resetsAt: end,
                                 reportedAmount: used,
                                 reportedUnit: "CU")
        let extra = value.oneShotCreativeUnits.isEmpty ? nil :
            CreditBalance(amount: oneShotRemaining, currency: "CU",
                          note: "追加購入CUの公式残高（購入枠ごとの期限はScenarioで確認）")
        return Snapshot(windows: [window], credit: extra, fetchedAt: fetchedAt)
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 &&
        value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) ||
            (97...122).contains(byte) || byte == 45 || byte == 95
        }
    }

    private static func validSecret(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 4_096 &&
        value.utf8.allSatisfy { $0 > 32 && $0 < 127 && $0 != 124 }
    }

    private static func validNumber(_ value: Double) -> Bool {
        value.isFinite && (0...9_007_199_254_740_991).contains(value)
    }

    private static func date(_ text: String) -> Date? {
        guard !text.isEmpty, text.utf8.count <= 64 else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func invalid() -> ParseError {
        .unsupported("Scenarioの認証情報またはCreative Units利用状況を確認できません")
    }
}
