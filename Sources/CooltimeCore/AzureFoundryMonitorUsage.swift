import Foundation

/// Exact token metrics for a Microsoft Cognitive Services / Foundry resource.
public enum AzureFoundryMonitorUsage {
    public struct Configuration: Sendable {
        public let subscriptionID: String
        public let resourceGroup: String
        public let accountName: String

        public var resourceID: String {
            "/subscriptions/\(subscriptionID)/resourceGroups/\(resourceGroup)/providers/Microsoft.CognitiveServices/accounts/\(accountName)"
        }
    }

    public struct Period: Equatable, Sendable {
        public let start: Date
        public let end: Date
    }

    private struct Response: Decodable {
        struct Metric: Decodable {
            struct Name: Decodable { let value: String }
            struct Series: Decodable {
                struct Point: Decodable { let timeStamp: String; let total: Double? }
                let data: [Point]
            }
            let name: Name
            let unit: String
            let timeseries: [Series]
        }
        let value: [Metric]
    }

    public static func configuration(from input: String) throws -> Configuration {
        let parts = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, uuid(parts[0]), safeName(parts[1]), safeName(parts[2]) else { throw invalid() }
        return Configuration(subscriptionID: parts[0], resourceGroup: parts[1], accountName: parts[2])
    }

    public static func previousSevenDays(now: Date) -> Period {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.startOfDay(for: now)
        return Period(start: calendar.date(byAdding: .day, value: -7, to: end)!, end: end)
    }

    public static func parse(_ data: Data, period: Period, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 8_000_000, period.end > period.start,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.value.count == 3 else { throw invalid() }
        let wanted = ["ProcessedPromptTokens", "GeneratedTokens", "TokenTransaction"]
        var totals: [String: Double] = [:]
        for metric in response.value {
            let name = metric.name.value
            guard wanted.contains(name), totals[name] == nil, metric.unit == "Count",
                  metric.timeseries.count <= 10_000 else { throw invalid() }
            var total = 0.0
            for series in metric.timeseries {
                guard series.data.count <= 10_000 else { throw invalid() }
                for point in series.data {
                    guard let timestamp = date(point.timeStamp),
                          timestamp >= period.start, timestamp < period.end else { throw invalid() }
                    if let value = point.total {
                        guard valid(value) else { throw invalid() }
                        total += value
                        guard valid(total) else { throw invalid() }
                    }
                }
            }
            totals[name] = total
        }
        guard let input = totals["ProcessedPromptTokens"], let output = totals["GeneratedTokens"],
              let all = totals["TokenTransaction"] else { throw invalid() }
        return Snapshot(windows: [
            UsageWindow(label: "Foundry入力・直近7 UTC日", reportedAmount: input, reportedUnit: "tokens"),
            UsageWindow(label: "Foundry出力・直近7 UTC日", reportedAmount: output, reportedUnit: "tokens"),
            UsageWindow(label: "Foundry推論合計・直近7 UTC日", reportedAmount: all, reportedUnit: "tokens")
        ], fetchedAt: fetchedAt)
    }

    private static func uuid(_ value: String) -> Bool {
        guard value.utf8.count == 36, UUID(uuidString: value) != nil else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) || byte == 45
        }
    }

    private static func safeName(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 90 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) ||
            byte == 45 || byte == 46 || byte == 95
        }
    }

    private static func date(_ value: String) -> Date? {
        guard !value.isEmpty, value.utf8.count <= 64 else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func valid(_ value: Double) -> Bool {
        value.isFinite && (0...9_007_199_254_740_991).contains(value)
    }

    private static func invalid() -> ParseError {
        .unsupported("Microsoft FoundryのAzure設定またはMonitor利用実績を確認できません")
    }
}
