import Foundation

/// Counts audit events for one Workspace user, using the Admin SDK Reports API.
public enum WorkspaceGeminiUsage {
    public static let scope = "https://www.googleapis.com/auth/admin.reports.audit.readonly"
    private static let application = "gemini_in_workspace_apps"
    private static let eventName = "feature_utilization"
    private static let reportKind = "admin#reports#activities"

    public struct Configuration: Sendable {
        public let projectID: String
        let email: String
    }

    private struct Report: Decodable {
        struct Activity: Decodable {
            struct ID: Decodable {
                let time: String
                let uniqueQualifier: String
            }
            struct Event: Decodable { let name: String }
            let id: ID
            let events: [Event]
        }
        let kind: String
        let items: [Activity]?
        let nextPageToken: String?
    }

    private struct ActivityKey: Hashable {
        let time: Date
        let qualifier: Int64
    }

    public static func configuration(from value: String) throws -> Configuration {
        let fields = value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 2,
              fields[0].range(of: #"\A[a-z][a-z0-9-]{4,28}[a-z0-9]\z"#, options: .regularExpression) != nil,
              fields[1].utf8.count <= 254,
              fields[1].range(of: #"\A[A-Za-z0-9._+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\z"#,
                              options: .regularExpression) != nil else {
            throw ParseError.unsupported("Google Cloud project ID|対象Workspaceユーザーのメールアドレス の形式で入力してください")
        }
        return Configuration(projectID: fields[0], email: fields[1])
    }

    public static func period(now: Date) -> DailyUsagePeriod {
        .previousSevenDays(now: now, lagHours: 24)
    }

    public static func fetch(config: Configuration, period: DailyUsagePeriod, fetchedAt: Date,
                             get: (String) async throws -> Data) async throws -> Snapshot {
        var pageToken: String?
        var seenTokens = Set<String>()
        var counts = [ActivityKey: Int]()
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        repeat {
            let data = try await get(url(config: config, period: period, pageToken: pageToken))
            guard data.count <= 2_000_000,
                  let report = try? JSONDecoder().decode(Report.self, from: data),
                  report.kind == reportKind else { throw invalid() }
            let activities = report.items ?? []
            guard activities.count <= 1000 else { throw invalid() }
            for activity in activities {
                guard let time = fractional.date(from: activity.id.time) ?? formatter.date(from: activity.id.time),
                      time >= period.start, time <= period.end,
                      let qualifier = Int64(activity.id.uniqueQualifier) else { throw invalid() }
                if time == period.end { continue }
                let key = ActivityKey(time: time, qualifier: qualifier)
                let count = activity.events.filter { $0.name == eventName }.count
                guard count > 0, counts[key].map({ $0 == count }) ?? true else { throw invalid() }
                counts[key] = count
            }
            pageToken = report.nextPageToken
            if let pageToken {
                guard !pageToken.isEmpty, pageToken.utf8.count <= 4096,
                      seenTokens.insert(pageToken).inserted, seenTokens.count < 100 else { throw invalid() }
            }
        } while pageToken != nil

        return Snapshot(windows: [UsageWindow(label: "Gemini監査イベント（\(period.label)）",
                                             reportedAmount: Double(counts.values.reduce(0, +)),
                                             reportedUnit: "件")], fetchedAt: fetchedAt)
    }

    private static func url(config: Configuration, period: DailyUsagePeriod, pageToken: String?) -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "admin.googleapis.com"
        components.path = "/admin/reports/v1/activity/users/\(config.email)/applications/\(application)"
        let formatter = ISO8601DateFormatter()
        var query = [URLQueryItem(name: "eventName", value: eventName),
                     URLQueryItem(name: "startTime", value: formatter.string(from: period.start)),
                     URLQueryItem(name: "endTime", value: formatter.string(from: period.end)),
                     URLQueryItem(name: "maxResults", value: "1000"),
                     URLQueryItem(name: "fields", value: "kind,nextPageToken,items(id(time,uniqueQualifier),events(name))")]
        if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        components.queryItems = query
        // Google parses query strings as form data. Preserve literal plus signs in opaque page tokens.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.string!
    }

    private static func invalid() -> ParseError {
        .unsupported("Google Workspace Geminiの監査実績を全件確認できません")
    }
}
