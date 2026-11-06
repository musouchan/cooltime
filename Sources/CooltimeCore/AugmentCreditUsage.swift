import Foundation

public enum AugmentCreditUsage {
    private struct Page: Decodable {
        struct Record: Decodable {
            let user_email: String?
            let service_account_name: String?
            let credits_consumed: Int64
            let date: String?
            let model_name: String?
        }
        struct Pagination: Decodable { let has_more: Bool; let next_cursor: String? }
        struct Metadata: Decodable {
            let effective_start_date: String
            let effective_end_date: String
            let generated_at: String
            let returned_record_count: Int
        }
        let records: [Record]
        let pagination: Pagination
        let metadata: Metadata
    }

    public static func configuration(from input: String) throws -> (email: String, token: String) {
        try UsageCredentials.parse(input)
    }

    public static func url(period: DailyUsagePeriod, cursor: String? = nil) -> String {
        var parts = URLComponents(string: "https://api.augmentcode.com/analytics/v0/credit-usage-by-user")!
        parts.queryItems = [URLQueryItem(name: "start_date", value: period.firstDay),
                            URLQueryItem(name: "end_date", value: period.lastDay),
                            URLQueryItem(name: "by_date", value: "false"),
                            URLQueryItem(name: "by_model", value: "false"),
                            URLQueryItem(name: "page_size", value: "500")]
        if let cursor { parts.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.string!
    }

    /// The API has no user filter. Discard other users' rows without persisting them.
    public static func fetch(email: String, period: DailyUsagePeriod, fetchedAt: Date,
                             get: (String) async throws -> Data) async throws -> Snapshot {
        var cursor: String?
        var cursors = Set<String>()
        var amount: Int64?
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for _ in 0..<20 {
            let data = try await get(url(period: period, cursor: cursor))
            guard data.count <= 8_000_000, let page = try? JSONDecoder().decode(Page.self, from: data),
                  page.records.count <= 500, page.metadata.returned_record_count == page.records.count,
                  page.metadata.effective_start_date == period.firstDay,
                  page.metadata.effective_end_date == period.lastDay,
                  let generated = iso.date(from: page.metadata.generated_at) ?? fractional.date(from: page.metadata.generated_at),
                  generated >= period.end, generated <= fetchedAt.addingTimeInterval(300) else { throw invalid() }
            for row in page.records {
                guard (row.user_email != nil) != (row.service_account_name != nil),
                      !(row.user_email ?? row.service_account_name ?? "").isEmpty,
                      row.date == nil, row.model_name == nil,
                      (0...9_007_199_254_740_991).contains(row.credits_consumed) else { throw invalid() }
                if row.user_email?.caseInsensitiveCompare(email) == .orderedSame {
                    guard amount == nil else { throw invalid() }
                    amount = row.credits_consumed
                }
            }
            if !page.pagination.has_more {
                guard let amount else {
                    throw ParseError.unsupported("対象ユーザーのAugment実績がありません。期間・メールアドレス・権限を確認してください")
                }
                return Snapshot(windows: [UsageWindow(label: "消費・\(period.label)",
                    reportedAmount: Double(amount), reportedUnit: "credits")], fetchedAt: fetchedAt)
            }
            guard !page.records.isEmpty, let next = page.pagination.next_cursor, !next.isEmpty,
                  next.utf8.count <= 4096, cursors.insert(next).inserted else { throw invalid() }
            cursor = next
        }
        throw ParseError.unsupported("Augmentの取得ページ数が上限を超えました。集計は表示しません")
    }

    private static func invalid() -> ParseError {
        .unsupported("Augmentの利用実績・期間・ページ情報を確認できません")
    }
}
