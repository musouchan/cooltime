import Foundation

/// One finalized UTC day of AI Agents - Advanced conversation export for one bot.
public enum ZendeskAIExportUsage {
    public struct Configuration: Sendable {
        public let subdomain: String
        public let organizationID: String
        public let botID: String
        public let token: String
    }

    private struct Links: Decodable {
        let date: String
        let urls: [String]
    }

    private struct Conversation: Decodable {
        let bot_id: String
        let conversation_id: String
        let test_mode: Bool
        let resolution_tier: String
    }

    public static func configuration(from input: String) throws -> Configuration {
        let fields = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4, fields[0].range(of: #"^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$"#, options: .regularExpression) != nil,
              fields[1].range(of: #"^[a-zA-Z0-9_-]{1,128}$"#, options: .regularExpression) != nil,
              fields[2].range(of: #"^[a-zA-Z0-9_-]{1,128}$"#, options: .regularExpression) != nil,
              !fields[3].isEmpty, fields[3].utf8.count <= 4096,
              fields[3].utf8.allSatisfy({ (33...126).contains($0) }),
              !fields[0].hasSuffix("-") else { throw invalid() }
        return Configuration(subdomain: fields[0], organizationID: fields[1],
                             botID: fields[2], token: fields[3])
    }

    public static func exportDay(now: Date) -> String {
        DailyUsagePeriod.day(Calendar(identifier: .gregorian).startOfDayUTC(now).addingTimeInterval(-86_400))
    }

    public static func endpoint(subdomain: String) -> String {
        "https://\(subdomain).zendesk.com/ai-agents/api/data-export/v3/get-signed-urls"
    }

    /// Validates all signed links before any download. Unexpected hosts or empty exports fail closed.
    public static func signedURLs(_ data: Data, day: String) throws -> [String] {
        guard data.count <= 100_000, let response = try? JSONDecoder().decode(Links.self, from: data),
              response.date == day, (1...20).contains(response.urls.count),
              Set(response.urls).count == response.urls.count,
              response.urls.allSatisfy({ url in
                  guard let components = URLComponents(string: url), let parsed = components.url else { return false }
                  return parsed.scheme == "https" && parsed.host == "storage.googleapis.com" &&
                         parsed.port == nil && parsed.user == nil && parsed.password == nil &&
                         parsed.path.hasSuffix(".json") && parsed.path.contains("/files/") &&
                         parsed.query != nil && !parsed.query!.isEmpty && parsed.fragment == nil
              }) else { throw invalid() }
        return response.urls
    }

    /// Exports can include customer data; only these four fields are decoded and nothing is persisted.
    public static func parse(_ files: [Data], botID: String, day: String, fetchedAt: Date) throws -> Snapshot {
        guard !files.isEmpty, files.count <= 20 else { throw invalid() }
        var seen = Set<String>()
        var verified = 0
        for data in files {
            guard data.count <= 10_000_000,
                  let conversations = try? JSONDecoder().decode([Conversation].self, from: data),
                  conversations.count <= 100_000 else { throw invalid() }
            for conversation in conversations {
                guard conversation.bot_id == botID, !conversation.conversation_id.isEmpty,
                      conversation.conversation_id.utf8.count <= 256,
                      seen.insert(conversation.conversation_id).inserted,
                      ["assisted_escalation", "contained_resolution", "core_resolution", "non_automated"].contains(conversation.resolution_tier)
                else { throw invalid() }
                if !conversation.test_mode && conversation.resolution_tier == "core_resolution" { verified += 1 }
            }
        }
        return Snapshot(windows: [UsageWindow(label: "Zendesk AI Agents・\(day) UTC 確認済み解決",
                                              reportedAmount: Double(verified), reportedUnit: "verified resolutions")],
                        fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Zendesk AI Agentsの確定済みエクスポートを確認できません")
    }
}

private extension Calendar {
    func startOfDayUTC(_ date: Date) -> Date {
        var utc = self
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.startOfDay(for: date)
    }
}
