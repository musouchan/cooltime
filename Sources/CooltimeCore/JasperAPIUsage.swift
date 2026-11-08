import Foundation

/// Jasper Public API content-generation request usage, not Jasper app subscription credits.
public enum JasperAPIUsage {
    public struct Period: Equatable, Sendable {
        public let start: Date
        public let end: Date
    }

    private struct Envelope: Decodable {
        struct UsageData: Decodable {
            struct Point: Decodable { let t: String; let v: Double }
            let requests: [Point]
        }
        let requestId: String
        let resource: String
        let data: UsageData
    }

    public static func previousSevenDays(now: Date) -> Period {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.startOfDay(for: now)
        return Period(start: calendar.date(byAdding: .day, value: -7, to: end)!, end: end)
    }

    public static func url(period: Period) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var components = URLComponents(string: "https://api.jasper.ai/v1/usage")!
        components.queryItems = [
            URLQueryItem(name: "start", value: f.string(from: period.start)),
            URLQueryItem(name: "end", value: f.string(from: period.end)),
            URLQueryItem(name: "granularity", value: "day")
        ]
        return components.string!
    }

    public static func parse(_ data: Data, period: Period, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 2_000_000,
              period.end > period.start,
              let value = try? JSONDecoder().decode(Envelope.self, from: data),
              !value.requestId.isEmpty, value.requestId.utf8.count <= 256,
              value.resource == "usage", value.data.requests.count <= 10_000 else { throw invalid() }
        var seen = Set<String>(), total = 0.0
        for point in value.data.requests {
            guard seen.insert(point.t).inserted,
                  let timestamp = date(point.t),
                  timestamp >= period.start, timestamp < period.end,
                  valid(point.v) else { throw invalid() }
            total += point.v
            guard valid(total) else { throw invalid() }
        }
        return Snapshot(windows: [
            UsageWindow(label: "Jasper API・直近7 UTC日",
                        reportedAmount: total, reportedUnit: "requests")
        ], fetchedAt: fetchedAt)
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
        .unsupported("Jasper APIの利用実績を確認できません")
    }
}
