import Foundation

public enum FigmaAIUsage {
    private struct Page: Decodable {
        struct Row: Decodable {
            let plan_id: String
            let user_id: String
            let user_email: String
            let day: String
            let editor_type: String
            let seat_credits_sum: Double
            let plan_credits_sum: Double
            let workspace_id: String?
            let team_id: String?
            let license_group_id: String?
        }
        let rows: [Row]
        let next_cursor: String?
        let has_next_page: Bool
    }

    public static func configuration(from input: String) throws -> (email: String, token: String) {
        try UsageCredentials.parse(input)
    }

    public static func url(email: String, period: DailyUsagePeriod, cursor: String? = nil) -> String {
        var parts = URLComponents(string: "https://api.figma.com/v1/ai_usage/daily")!
        parts.queryItems = [URLQueryItem(name: "start_date", value: period.firstDay),
                            URLQueryItem(name: "end_date", value: period.lastDay),
                            URLQueryItem(name: "user_email", value: email),
                            URLQueryItem(name: "limit", value: "1000")]
        if let cursor { parts.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.string!
    }

    /// Uses opaque cursors only on the fixed official endpoint. No partial totals.
    public static func fetch(email: String, period: DailyUsagePeriod, fetchedAt: Date,
                             get: (String) async throws -> Data) async throws -> Snapshot {
        var cursor: String?
        var cursors = Set<String>()
        var grains = Set<[String?]>()
        var identity: [String]?
        var seat = 0.0, plan = 0.0
        let maximum = 9_007_199_254_740_991.0
        for _ in 0..<20 {
            let data = try await get(url(email: email, period: period, cursor: cursor))
            guard data.count <= 8_000_000, let page = try? JSONDecoder().decode(Page.self, from: data),
                  page.rows.count <= 1000 else { throw invalid() }
            for row in page.rows {
                let rowIdentity = [row.plan_id, row.user_id]
                guard row.user_email.caseInsensitiveCompare(email) == .orderedSame,
                      !row.plan_id.isEmpty, !row.user_id.isEmpty, !row.editor_type.isEmpty,
                      period.contains(row.day), identity == nil || identity == rowIdentity,
                      grains.insert([row.plan_id, row.user_id, row.day, row.editor_type,
                                     row.workspace_id, row.team_id, row.license_group_id]).inserted,
                      (0...maximum - seat).contains(row.seat_credits_sum),
                      (0...maximum - plan).contains(row.plan_credits_sum) else { throw invalid() }
                identity = rowIdentity
                seat += row.seat_credits_sum
                plan += row.plan_credits_sum
            }
            if !page.has_next_page {
                guard identity != nil else {
                    throw ParseError.unsupported("対象ユーザーのFigma実績がありません。期間・メールアドレス・権限を確認してください")
                }
                return Snapshot(windows: [
                    UsageWindow(label: "個人割当の消費・\(period.label)", reportedAmount: seat, reportedUnit: "credits"),
                    UsageWindow(label: "共有枠の消費・\(period.label)", reportedAmount: plan, reportedUnit: "credits")
                ], fetchedAt: fetchedAt)
            }
            guard !page.rows.isEmpty, let next = page.next_cursor, !next.isEmpty,
                  next.utf8.count <= 4096, cursors.insert(next).inserted else { throw invalid() }
            cursor = next
        }
        throw ParseError.unsupported("Figmaの取得ページ数が上限を超えました。集計は表示しません")
    }

    private static func invalid() -> ParseError {
        .unsupported("Figmaの利用実績・対象・期間・ページ情報を確認できません")
    }
}
