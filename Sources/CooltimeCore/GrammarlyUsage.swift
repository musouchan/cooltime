import Foundation

public enum GrammarlyUsage {
    public struct Configuration {
        public let userID: Int64
        public let clientID: String
        public let secret: String
    }
    private struct Token: Decodable { let access_token: String; let token_type: String? }
    private struct Page: Decodable {
        struct User: Decodable { let id: Int64; let prompt_count: Int64 }
        struct Paging: Decodable { let has_more: Bool; let next_cursor: String?; let page_size: Int }
        let data: [User]
        let paging: Paging
    }
    public static func configuration(_ input: String) throws -> Configuration {
        let parts = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let id = Int64(parts[0]), id > 0,
              parts[1...].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else { throw invalid() }
        return Configuration(userID: id, clientID: parts[1], secret: parts[2])
    }
    public static func tokenBody(_ config: Configuration) -> Data {
        func encode(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!
        }
        return Data(("grant_type=client_credentials&client_id=" + encode(config.clientID)
                     + "&client_secret=" + encode(config.secret) + "&scope=analytics-api%3Aread").utf8)
    }
    public static func token(_ data: Data) throws -> String {
        guard let value = try? JSONDecoder().decode(Token.self, from: data),
              !value.access_token.isEmpty, value.access_token.utf8.count <= 16384,
              value.access_token.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }),
              value.token_type == nil || value.token_type?.lowercased() == "bearer" else { throw invalid() }
        return value.access_token
    }
    public static func url(period: DailyUsagePeriod, cursor: String?) -> String {
        var c = URLComponents(string: "https://api.grammarly.com/ecosystem/api/v2/analytics/users/")!
        c.queryItems = [URLQueryItem(name: "date_from", value: period.firstDay),
                        URLQueryItem(name: "date_to", value: period.lastDay),
                        URLQueryItem(name: "limit", value: "400")]
        if let cursor { c.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.string!
    }
    public static func fetch(userID: Int64, period: DailyUsagePeriod, fetchedAt: Date,
                             get: (String) async throws -> Data) async throws -> Snapshot {
        var cursor: String?
        var seenCursors = Set<String>()
        var seenUsers = Set<Int64>()
        var amount: Int64?
        for _ in 0..<20 {
            let data = try await get(url(period: period, cursor: cursor))
            guard data.count <= 8_000_000, let page = try? JSONDecoder().decode(Page.self, from: data),
                  page.data.count <= 400, page.paging.page_size == page.data.count else { throw invalid() }
            for user in page.data {
                guard user.id > 0, (0...9_007_199_254_740_991).contains(user.prompt_count),
                      seenUsers.insert(user.id).inserted else { throw invalid() }
                if user.id == userID { amount = user.prompt_count }
            }
            if !page.paging.has_more {
                guard let amount else { throw ParseError.unsupported("対象ユーザーのGrammarly利用実績がありません") }
                return Snapshot(windows: [UsageWindow(label: "AI使用・\(period.label)", reportedAmount: Double(amount),
                                                       reportedUnit: "prompts")], fetchedAt: fetchedAt)
            }
            guard !page.data.isEmpty, let next = page.paging.next_cursor, !next.isEmpty,
                  next.utf8.count <= 4096, seenCursors.insert(next).inserted else { throw invalid() }
            cursor = next
        }
        throw invalid()
    }
    private static func invalid() -> ParseError { .unsupported("Grammarlyの認証情報・利用実績・ページ情報を確認できません") }
}
