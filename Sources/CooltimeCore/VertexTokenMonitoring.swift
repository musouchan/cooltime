import Foundation

/// Cloud Monitoring's publisher model token_count DELTA metric, scoped to a model and region.
public enum VertexTokenMonitoring {
    public struct Configuration: Sendable {
        public let projectID: String
        public let location: String
        public let publisher: String
        public let modelID: String
    }

    public struct Page: Sendable {
        public let input: Double
        public let output: Double
        public let seriesCount: Int
        public let nextPageToken: String?
    }

    private struct Response: Decodable {
        struct Series: Decodable {
            struct Metric: Decodable { let type: String; let labels: [String: String] }
            struct Resource: Decodable { let type: String; let labels: [String: String] }
            struct Point: Decodable {
                struct Value: Decodable { let int64Value: String }
                let value: Value
            }
            let metric: Metric
            let resource: Resource
            let metricKind: String
            let valueType: String
            let points: [Point]
        }
        let timeSeries: [Series]?
        let nextPageToken: String?
    }

    public static func configuration(from input: String) throws -> Configuration {
        let fields = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4, fields.allSatisfy({
            !$0.isEmpty && $0.utf8.count <= 128 && $0.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || [45, 46, 95].contains(byte)
            }
        }) else { throw invalid() }
        return Configuration(projectID: fields[0], location: fields[1], publisher: fields[2], modelID: fields[3])
    }

    public static func period(now: Date) -> DailyUsagePeriod {
        .previousSevenDays(now: now, lagHours: 6)
    }

    public static func url(config: Configuration, period: DailyUsagePeriod, pageToken: String? = nil) throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "monitoring.googleapis.com"
        components.path = "/v3/projects/\(config.projectID)/timeSeries"
        let filter = "metric.type = \"aiplatform.googleapis.com/publisher/online_serving/token_count\" AND resource.type = \"aiplatform.googleapis.com/PublisherModel\" AND resource.labels.location = \"\(config.location)\" AND resource.labels.publisher = \"\(config.publisher)\" AND resource.labels.model_user_id = \"\(config.modelID)\""
        let formatter = ISO8601DateFormatter()
        var items = [URLQueryItem(name: "filter", value: filter),
                     URLQueryItem(name: "interval.startTime", value: formatter.string(from: period.start)),
                     URLQueryItem(name: "interval.endTime", value: formatter.string(from: period.end)),
                     URLQueryItem(name: "view", value: "FULL"),
                     URLQueryItem(name: "aggregation.alignmentPeriod", value: "86400s"),
                     URLQueryItem(name: "aggregation.perSeriesAligner", value: "ALIGN_SUM"),
                     URLQueryItem(name: "pageSize", value: "1000")]
        if let pageToken {
            guard !pageToken.isEmpty, pageToken.utf8.count <= 2048 else { throw invalid() }
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = items
        guard let url = components.url else { throw invalid() }
        return url.absoluteString
    }

    public static func parsePage(_ data: Data, config: Configuration) throws -> Page {
        guard data.count <= 3_000_000, let response = try? JSONDecoder().decode(Response.self, from: data),
              let series = response.timeSeries, series.count <= 1000,
              response.nextPageToken.map({ !$0.isEmpty && $0.utf8.count <= 2048 }) ?? true
        else { throw invalid() }
        var input = 0.0, output = 0.0
        for item in series {
            guard item.metric.type == "aiplatform.googleapis.com/publisher/online_serving/token_count",
                  item.resource.type == "aiplatform.googleapis.com/PublisherModel",
                  item.resource.labels["location"] == config.location,
                  item.resource.labels["publisher"] == config.publisher,
                  item.resource.labels["model_user_id"] == config.modelID,
                  item.metricKind == "DELTA", item.valueType == "INT64",
                  let kind = item.metric.labels["type"], ["input", "output"].contains(kind),
                  item.points.count <= 1000 else { throw invalid() }
            for point in item.points {
                guard let count = UInt64(point.value.int64Value), count <= 9_007_199_254_740_991 else { throw invalid() }
                if kind == "input" { input += Double(count) } else { output += Double(count) }
            }
        }
        return Page(input: input, output: output, seriesCount: series.count,
                    nextPageToken: response.nextPageToken)
    }

    public static func snapshot(input: Double, output: Double, period: DailyUsagePeriod, fetchedAt: Date) throws -> Snapshot {
        guard input.isFinite, output.isFinite, input >= 0, output >= 0 else { throw invalid() }
        return Snapshot(windows: [
            UsageWindow(label: "Vertex AI・入力トークン \(period.label)", reportedAmount: input, reportedUnit: "tokens"),
            UsageWindow(label: "Vertex AI・出力トークン \(period.label)", reportedAmount: output, reportedUnit: "tokens")
        ], fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Vertex AIの指定モデル・地域のCloud Monitoringトークン実績を確認できません")
    }
}
