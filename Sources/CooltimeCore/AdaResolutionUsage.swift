import Foundation

/// Ada's explicit automated-resolution classification, not its billable resolution ledger.
public enum AdaResolutionUsage {
    public struct Configuration: Sendable {
        let handle: String
        public let token: String
    }

    private struct Page: Decodable {
        struct Conversation: Decodable {
            let _id: String
            let automated_resolution_classification: String?
            let is_test_user: Bool
        }
        struct Metadata: Decodable { let next_page_uri: String? }
        let data: [Conversation]
        let meta: Metadata?
    }

    public static func configuration(from value: String) throws -> Configuration {
        let fields = value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 2,
              fields[0].range(of: #"\A[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\z"#, options: .regularExpression) != nil,
              !fields[1].isEmpty, fields[1].utf8.count <= 4096,
              fields[1].utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ParseError.unsupported("Ada agent handle|Data Export API key の形式で入力してください")
        }
        return Configuration(handle: fields[0], token: fields[1])
    }

    public static func previousDay(now: Date) -> String {
        DailyUsagePeriod.day(now.addingTimeInterval(-86_400))
    }

    public static func initialURL(config: Configuration, day: String) -> String {
        let start = ISO8601DateFormatter().date(from: "\(day)T00:00:00Z")!
        let nextDay = DailyUsagePeriod.day(start.addingTimeInterval(86_400))
        var components = URLComponents(string: "https://\(config.handle).ada.support/api/v2/export/conversations")!
        components.queryItems = [URLQueryItem(name: "created_since", value: "\(day)T00:00:00Z"),
                                 URLQueryItem(name: "created_to", value: "\(nextDay)T00:00:00Z"),
                                 URLQueryItem(name: "page_size", value: "100")]
        return components.string!
    }

    public static func fetch(config: Configuration, now: Date,
                             get: (String) async throws -> Data) async throws -> Snapshot {
        let day = previousDay(now: now)
        var url: String? = initialURL(config: config, day: day)
        var seenURLs = Set<String>(), seenIDs = Set<String>()
        var resolved = 0, classified = 0, eligible = 0
        for _ in 0..<100 {
            guard let current = url, seenURLs.insert(current).inserted else { throw invalid() }
            let data = try await get(current)
            guard data.count <= 10_000_000, let page = try? JSONDecoder().decode(Page.self, from: data),
                  page.data.count <= 100 else { throw invalid() }
            for conversation in page.data {
                guard !conversation._id.isEmpty, conversation._id.utf8.count <= 256,
                      seenIDs.insert(conversation._id).inserted else { throw invalid() }
                if conversation.is_test_user { continue }
                eligible += 1
                if let result = conversation.automated_resolution_classification {
                    guard result == "Resolved" || result == "Not Resolved" else { throw invalid() }
                    classified += 1
                    if result == "Resolved" { resolved += 1 }
                }
            }
            if let next = page.meta?.next_page_uri, !next.isEmpty {
                url = try validatedNextURL(next, handle: config.handle)
            } else {
                guard eligible == 0 || classified > 0 else { throw invalid() }
                return Snapshot(windows: [UsageWindow(label: "Ada自動解決分類・\(day) UTC",
                                                     reportedAmount: Double(resolved), reportedUnit: "件")], fetchedAt: now)
            }
        }
        throw invalid()
    }

    private static func validatedNextURL(_ value: String, handle: String) throws -> String {
        guard value.utf8.count <= 4_096 else { throw invalid() }
        let absolute = value.hasPrefix("/") ? "https://\(handle).ada.support\(value)" : value
        guard let url = URLComponents(string: absolute), url.scheme == "https",
              url.host == "\(handle).ada.support", url.port == nil, url.user == nil,
              url.password == nil, url.fragment == nil, url.path == "/api/v2/export/conversations",
              let items = url.queryItems,
              items.contains(where: { $0.name == "created_since" && $0.value != nil }),
              items.contains(where: { $0.name == "created_to" && $0.value != nil }) else { throw invalid() }
        return absolute
    }

    private static func invalid() -> ParseError {
        .unsupported("Adaの自動解決分類を全件確認できません")
    }
}
