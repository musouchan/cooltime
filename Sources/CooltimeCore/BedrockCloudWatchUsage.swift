import Foundation

/// Exact Amazon Bedrock runtime metrics published to CloudWatch.
public enum BedrockCloudWatchUsage {
    public struct Configuration: Sendable {
        public let profile: String
        public let region: String
        public let modelID: String
    }

    public struct Period: Equatable, Sendable {
        public let start: Date
        public let end: Date
    }

    private struct Response: Decodable {
        struct Result: Decodable {
            let Id: String
            let Values: [Double]
            let StatusCode: String
        }
        let MetricDataResults: [Result]
    }

    public static func configuration(from input: String) throws -> Configuration {
        let parts = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              safeToken(parts[0], allowed: ".-_"),
              safeToken(parts[1], allowed: "-"),
              safeModelID(parts[2]) else { throw invalid() }
        return Configuration(profile: parts[0], region: parts[1], modelID: parts[2])
    }

    public static func previousSevenDays(now: Date) -> Period {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.startOfDay(for: now)
        return Period(start: calendar.date(byAdding: .day, value: -7, to: end)!, end: end)
    }

    public static func queryJSON(modelID: String) throws -> String {
        guard safeModelID(modelID) else { throw invalid() }
        let names = [("input", "InputTokenCount"), ("output", "OutputTokenCount"),
                     ("invocations", "Invocations")]
        let value: [[String: Any]] = names.map { id, metric in
            ["Id": id, "MetricStat": [
                "Metric": ["Namespace": "AWS/Bedrock", "MetricName": metric,
                           "Dimensions": [["Name": "ModelId", "Value": modelID]]],
                "Period": 86_400, "Stat": "Sum"
            ], "ReturnData": true]
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw invalid() }
        return text
    }

    public static func parse(_ data: Data, period: Period, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 4_000_000, period.end > period.start,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.MetricDataResults.count == 3 else { throw invalid() }
        var totals: [String: Double] = [:]
        for result in response.MetricDataResults {
            guard ["input", "output", "invocations"].contains(result.Id),
                  totals[result.Id] == nil, result.StatusCode == "Complete",
                  result.Values.count <= 10_000 else { throw invalid() }
            var total = 0.0
            for value in result.Values {
                guard valid(value) else { throw invalid() }
                total += value
                guard valid(total) else { throw invalid() }
            }
            totals[result.Id] = total
        }
        guard let input = totals["input"], let output = totals["output"],
              let invocations = totals["invocations"] else { throw invalid() }
        return Snapshot(windows: [
            UsageWindow(label: "Bedrock入力・直近7 UTC日", reportedAmount: input, reportedUnit: "tokens"),
            UsageWindow(label: "Bedrock出力・直近7 UTC日", reportedAmount: output, reportedUnit: "tokens"),
            UsageWindow(label: "Bedrock呼出・直近7 UTC日", reportedAmount: invocations, reportedUnit: "requests")
        ], fetchedAt: fetchedAt)
    }

    private static func safeToken(_ value: String, allowed: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) ||
            allowed.utf8.contains(byte)
        }
    }

    private static func safeModelID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) ||
            [45, 46, 47, 58, 95].contains(byte)
        }
    }

    private static func valid(_ value: Double) -> Bool {
        value.isFinite && (0...9_007_199_254_740_991).contains(value)
    }

    private static func invalid() -> ParseError {
        .unsupported("Amazon BedrockのAWS設定またはCloudWatch利用実績を確認できません")
    }
}
