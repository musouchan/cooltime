import Foundation

/// Counts conversations in which Fin participated. This is not a billable resolution count.
public enum IntercomFinConversations {
    public struct Period: Sendable {
        public let start: Date
        public let end: Date
    }

    private struct SearchResult: Decodable {
        let type: String
        let total_count: Int
        let conversations: [Conversation]

        struct Conversation: Decodable { let id: String }
    }

    public static func period(now: Date) -> Period {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.startOfDay(for: now)
        return Period(start: calendar.date(byAdding: .day, value: -7, to: end)!, end: end)
    }

    public static func requestBody(period: Period) throws -> Data {
        guard period.end > period.start else { throw invalid() }
        let filters: [[String: Any]] = [
            ["field": "created_at", "operator": ">", "value": Int(period.start.timeIntervalSince1970)],
            ["field": "created_at", "operator": "<", "value": Int(period.end.timeIntervalSince1970) - 1],
            ["field": "ai_agent_participated", "operator": "=", "value": true],
            ["field": "ai_agent.source_type", "operator": "!=", "value": "fin_preview"],
            ["field": "ai_agent.source_type", "operator": "!=", "value": "workflow_preview"]
        ]
        return try JSONSerialization.data(withJSONObject: ["query": ["operator": "AND", "value": filters],
                                                       "pagination": ["per_page": 1]])
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 1_000_000,
              let result = try? JSONDecoder().decode(SearchResult.self, from: data),
              result.type == "conversation.list", result.total_count >= 0,
              result.total_count <= 9_007_199_254_740_991,
              result.conversations.count <= 1,
              result.conversations.allSatisfy({ !$0.id.isEmpty }) else { throw invalid() }
        return Snapshot(windows: [UsageWindow(label: "Fin参加会話・直近7 UTC日（当日除く）",
                                              reportedAmount: Double(result.total_count),
                                              reportedUnit: "件")], fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Intercom Finの会話件数を確認できません")
    }
}
