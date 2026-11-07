import Foundation

public enum WorkspaceGeminiAuditUsage {
    private static let application = "gemini_in_workspace_apps"
    private static let eventName = "feature_utilization"
    private static let pageSize = 1000
    private static let pageLimit = 30

    private struct Report: Decodable {
        struct Activity: Decodable {
            struct ID: Decodable {
                let time: String
                let uniqueQualifier: String
                let applicationName: String
            }
            struct Actor: Decodable { let email: String }
            struct Event: Decodable { let name: String; let type: String }

            let id: ID
            let actor: Actor
            let events: [Event]
        }

        let kind: String
        let items: [Activity]?
        let nextPageToken: String?
    }

    public static func email(from input: String) throws -> String {
        let email = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#
        guard email.utf8.count <= 254, email.range(of: pattern, options: .regularExpression) != nil else {
            throw ParseError.unsupported("対象ユーザーのWorkspaceプライマリメールアドレスを入力してください")
        }
        return email
    }

    public static func period(now: Date) -> DailyUsagePeriod {
        // Allow a full day for audit events to arrive before counting completed UTC days.
        .previousSevenDays(now: now, lagHours: 24)
    }

    public static func fetch(email input: String, period: DailyUsagePeriod, fetchedAt: Date,
                             loadPage: (String) async throws -> Data) async throws -> Snapshot {
        let user = try email(from: input)
        let time = ISO8601DateFormatter()
        let fractionalTime = ISO8601DateFormatter()
        fractionalTime.formatOptions.insert(.withFractionalSeconds)
        var tokens = Set<String>()
        var records = Set<String>()
        var nextPageToken: String?

        repeat {
            try Task.checkCancellation()
            var components = URLComponents()
            components.scheme = "https"
            components.host = "admin.googleapis.com"
            components.path = "/admin/reports/v1/activity/users/\(user)/applications/\(application)"
            var query = [
                URLQueryItem(name: "eventName", value: eventName),
                URLQueryItem(name: "startTime", value: time.string(from: period.start)),
                URLQueryItem(name: "endTime", value: time.string(from: period.end)),
                URLQueryItem(name: "maxResults", value: String(pageSize)),
                URLQueryItem(name: "fields", value: "kind,nextPageToken,items(id(time,uniqueQualifier,applicationName),actor(email),events(type,name))")
            ]
            if let nextPageToken { query.append(URLQueryItem(name: "pageToken", value: nextPageToken)) }
            components.queryItems = query
            // Google parses query parameters using form encoding, including literal plus signs.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            guard let url = components.url else { throw invalid() }
            let data = try await loadPage(url.absoluteString)
            guard data.count <= 2_000_000, let report = try? JSONDecoder().decode(Report.self, from: data),
                  report.kind == "reports#activities", (report.items?.count ?? 0) <= pageSize else { throw invalid() }

            for record in report.items ?? [] {
                guard record.id.applicationName == application,
                      record.actor.email.caseInsensitiveCompare(user) == .orderedSame,
                      record.events.contains(where: { $0.name == eventName && $0.type == "ai_usage_event" }),
                      Int64(record.id.uniqueQualifier) != nil,
                      let timestamp = fractionalTime.date(from: record.id.time) ?? time.date(from: record.id.time),
                      timestamp >= period.start, timestamp <= period.end else { throw invalid() }
                if timestamp < period.end {
                    records.insert("\(timestamp.timeIntervalSince1970)|\(record.id.uniqueQualifier)")
                }
            }

            nextPageToken = report.nextPageToken
            if let nextPageToken {
                guard !nextPageToken.isEmpty, nextPageToken.utf8.count <= 2048,
                      tokens.insert(nextPageToken).inserted, tokens.count < pageLimit else { throw invalid() }
            }
        } while nextPageToken != nil

        let window = UsageWindow(label: "Workspace Gemini・監査ログ件数 \(period.label)",
                                 reportedAmount: Double(records.count), reportedUnit: "件")
        return Snapshot(windows: [window], fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Workspace Geminiの監査ログを指定ユーザー・期間で集計できません")
    }
}
