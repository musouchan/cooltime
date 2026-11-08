import Foundation

/// Project-wide, completed Gemini Developer API requests from Cloud Monitoring.
public enum GeminiAPIRequestUsage {
    private static let metric = "serviceruntime.googleapis.com/api/request_count"
    private static let service = "generativelanguage.googleapis.com"
    private static let resourceType = "consumed_api"

    private struct Page: Decodable {
        struct Series: Decodable {
            struct Metric: Decodable { let type: String }
            struct Resource: Decodable { let type: String; let labels: [String: String] }
            struct Point: Decodable {
                struct Interval: Decodable { let endTime: String }
                struct Value: Decodable { let int64Value: String }
                let interval: Interval
                let value: Value
            }
            let metric: Metric
            let resource: Resource
            let valueType: String
            let points: [Point]
        }
        let timeSeries: [Series]?
        let nextPageToken: String?
        let executionErrors: [ExecutionError]?

        struct ExecutionError: Decodable { let code: Int? }
    }

    public static func projectID(from input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"\A[a-z][a-z0-9-]{4,28}[a-z0-9]\z"#, options: .regularExpression) != nil else {
            throw ParseError.unsupported("Gemini APIを利用するGoogle Cloud project IDを入力してください")
        }
        return value
    }

    public static func period(now: Date) -> DailyUsagePeriod {
        .previousSevenDays(now: now, lagHours: 1)
    }

    public static func fetch(projectID input: String, period: DailyUsagePeriod, fetchedAt: Date,
                             loadPage: (String) async throws -> Data) async throws -> Snapshot {
        let project = try projectID(from: input)
        let iso = ISO8601DateFormatter()
        var points: [Date: Int64] = [:]
        var next: String?
        var tokens = Set<String>()
        repeat {
            try Task.checkCancellation()
            var components = URLComponents()
            components.scheme = "https"
            components.host = "monitoring.googleapis.com"
            components.path = "/v3/projects/\(project)/timeSeries"
            var query = [
                URLQueryItem(name: "filter", value: "metric.type = \"\(metric)\" AND resource.type = \"\(resourceType)\" AND resource.labels.service = \"\(service)\" AND resource.labels.project_id = \"\(project)\""),
                URLQueryItem(name: "interval.startTime", value: iso.string(from: period.start)),
                URLQueryItem(name: "interval.endTime", value: iso.string(from: period.end)),
                URLQueryItem(name: "view", value: "FULL"),
                URLQueryItem(name: "aggregation.alignmentPeriod", value: "86400s"),
                URLQueryItem(name: "aggregation.perSeriesAligner", value: "ALIGN_SUM"),
                URLQueryItem(name: "aggregation.crossSeriesReducer", value: "REDUCE_SUM"),
                URLQueryItem(name: "aggregation.groupByFields", value: "resource.labels.project_id"),
                URLQueryItem(name: "aggregation.groupByFields", value: "resource.labels.service"),
                URLQueryItem(name: "pageSize", value: "100")
            ]
            if let next { query.append(URLQueryItem(name: "pageToken", value: next)) }
            components.queryItems = query
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            guard let url = components.url else { throw invalid() }
            let data = try await loadPage(url.absoluteString)
            guard data.count <= 1_000_000, let page = try? JSONDecoder().decode(Page.self, from: data),
                  page.executionErrors?.isEmpty ?? true else { throw invalid() }

            for series in page.timeSeries ?? [] {
                guard series.metric.type == metric, series.resource.type == resourceType,
                      series.resource.labels["project_id"] == project, series.resource.labels["service"] == service,
                      series.valueType == "INT64", series.points.count <= 7 else { throw invalid() }
                for point in series.points {
                    guard let end = iso.date(from: point.interval.endTime), end > period.start, end <= period.end,
                          end.timeIntervalSince(period.start).truncatingRemainder(dividingBy: 86_400) == 0,
                          let amount = Int64(point.value.int64Value), (0...9_007_199_254_740_991).contains(amount),
                          points.updateValue(amount, forKey: end) == nil else { throw invalid() }
                }
            }

            next = page.nextPageToken
            if let next {
                guard !next.isEmpty, next.utf8.count <= 4096,
                      tokens.insert(next).inserted, tokens.count < 20 else { throw invalid() }
            }
        } while next != nil

        guard !points.isEmpty else {
            throw ParseError.unsupported("指定した期間にGemini APIのCloud Monitoring指標がありません")
        }
        let count = points.values.reduce(0, +)
        guard count <= 9_007_199_254_740_991 else { throw invalid() }
        return Snapshot(windows: [UsageWindow(label: "Gemini API・完了リクエスト \(period.label)",
                                              reportedAmount: Double(count), reportedUnit: "件")], fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Gemini APIのリクエスト実績を全件取得できません")
    }
}
