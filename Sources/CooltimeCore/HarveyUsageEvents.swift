import Foundation

/// Counts workspace events from Harvey's documented v2 Usage History API.
/// Usage history contains no prompts, but may contain sensitive resource names;
/// only aggregate counts leave this parser.
public enum HarveyUsageEvents {
    public struct Configuration: Sendable {
        public let region: String
        public let token: String
    }

    private struct Response: Decodable {
        struct Event: Decodable {
            let unique_usage_id: String
            let product_surface_area: String
        }
        let events: [Event]
    }

    public static func configuration(from value: String) throws -> Configuration {
        let fields = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 2, ["US", "EU", "AU"].contains(fields[0]),
              !fields[1].isEmpty, fields[1].utf8.count <= 2048,
              fields[1].utf8.allSatisfy({ (33...126).contains($0) }) else { throw invalid() }
        return Configuration(region: fields[0], token: fields[1])
    }

    public static func url(region: String, now: Date) throws -> String {
        let host: String
        switch region {
        case "US": host = "api.harvey.ai"
        case "EU": host = "eu.api.harvey.ai"
        case "AU": host = "au.api.harvey.ai"
        default: throw invalid()
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.startOfDay(for: now)
        let start = end.addingTimeInterval(-86_400)
        return "https://\(host)/api/v2/history/usage?start_time=\(Int(start.timeIntervalSince1970))&end_time=\(Int(end.timeIntervalSince1970) - 1)"
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 10_000_000,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.events.count <= 100_000 else { throw invalid() }
        var ids = Set<String>()
        var counts: [String: Int] = [:]
        let areas = Set(["ASSISTANT", "VAULT", "PLAYBOOK", "WORKFLOW", "WORD", "OUTLOOK", "DRAFT"])
        for event in response.events {
            guard !event.unique_usage_id.isEmpty, event.unique_usage_id.utf8.count <= 128,
                  ids.insert(event.unique_usage_id).inserted,
                  areas.contains(event.product_surface_area) else { throw invalid() }
            counts[event.product_surface_area, default: 0] += 1
        }
        let windows = areas.sorted().compactMap { area -> UsageWindow? in
            guard let count = counts[area] else { return nil }
            return UsageWindow(label: "Harvey \(area)・前UTC日", reportedAmount: Double(count), reportedUnit: "events")
        }
        return Snapshot(windows: windows.isEmpty
                        ? [UsageWindow(label: "Harvey利用イベント・前UTC日", reportedAmount: 0, reportedUnit: "events")]
                        : windows, fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Harveyの公式Usage History v2から利用イベントを確認できません")
    }
}
