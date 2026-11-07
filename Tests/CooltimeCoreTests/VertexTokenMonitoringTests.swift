import XCTest
@testable import CooltimeCore

final class VertexTokenMonitoringTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")!
    private var config: VertexTokenMonitoring.Configuration {
        get throws { try VertexTokenMonitoring.configuration(from: "my-project|us-central1|google|gemini-2.5-pro") }
    }

    func testBuildsModelScopedOfficialMonitoringQuery() throws {
        let cfg = try config
        let url = try VertexTokenMonitoring.url(config: cfg, period: VertexTokenMonitoring.period(now: now), pageToken: "page/2")
        let query = Dictionary(uniqueKeysWithValues: URLComponents(string: url)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(URLComponents(string: url)?.host, "monitoring.googleapis.com")
        XCTAssertTrue(query["filter"]!.contains("resource.labels.model_user_id = \"gemini-2.5-pro\""))
        XCTAssertEqual(query["aggregation.perSeriesAligner"], "ALIGN_SUM")
        XCTAssertEqual(query["pageToken"], "page/2")
        XCTAssertEqual(query["interval.startTime"], "2026-11-01T00:00:00Z")
        XCTAssertThrowsError(try VertexTokenMonitoring.configuration(from: "project|us-central1|google|bad\" OR true"))
    }

    func testParsesInputOutputSeriesAndPaginationWithoutInventingBalance() throws {
        let json = """
        {"timeSeries":[
         {"metric":{"type":"aiplatform.googleapis.com/publisher/online_serving/token_count","labels":{"type":"input"}},
          "resource":{"type":"aiplatform.googleapis.com/PublisherModel","labels":{"location":"us-central1","publisher":"google","model_user_id":"gemini-2.5-pro"}},
          "metricKind":"DELTA","valueType":"INT64","points":[{"value":{"int64Value":"120"}},{"value":{"int64Value":"30"}}]},
         {"metric":{"type":"aiplatform.googleapis.com/publisher/online_serving/token_count","labels":{"type":"output"}},
          "resource":{"type":"aiplatform.googleapis.com/PublisherModel","labels":{"location":"us-central1","publisher":"google","model_user_id":"gemini-2.5-pro"}},
          "metricKind":"DELTA","valueType":"INT64","points":[{"value":{"int64Value":"22"}}]}],"nextPageToken":"abc"}
        """
        let page = try VertexTokenMonitoring.parsePage(Data(json.utf8), config: config)
        XCTAssertEqual(page.input, 150)
        XCTAssertEqual(page.output, 22)
        XCTAssertEqual(page.seriesCount, 2)
        XCTAssertEqual(page.nextPageToken, "abc")
        let snapshot = try VertexTokenMonitoring.snapshot(input: page.input, output: page.output,
                                                          period: VertexTokenMonitoring.period(now: now), fetchedAt: now)
        XCTAssertEqual(snapshot.windows[0].reportedAmount, 150)
        XCTAssertEqual(snapshot.windows[1].reportedAmount, 22)
        XCTAssertNil(snapshot.windows[0].remainingCount)
        XCTAssertNil(snapshot.credit)
    }

    func testRejectsOtherModelMalformedAndNegativeMetrics() throws {
        let cfg = try config
        for body in ["{}", #"{"timeSeries":[{}]}"#,
                     #"{"timeSeries":[{"metric":{"type":"aiplatform.googleapis.com/publisher/online_serving/token_count","labels":{"type":"input"}},"resource":{"type":"aiplatform.googleapis.com/PublisherModel","labels":{"location":"us-central1","publisher":"google","model_user_id":"other"}},"metricKind":"DELTA","valueType":"INT64","points":[{"value":{"int64Value":"1"}}]}]}"#,
                     #"{"timeSeries":[{"metric":{"type":"aiplatform.googleapis.com/publisher/online_serving/token_count","labels":{"type":"input"}},"resource":{"type":"aiplatform.googleapis.com/PublisherModel","labels":{"location":"us-central1","publisher":"google","model_user_id":"gemini-2.5-pro"}},"metricKind":"DELTA","valueType":"INT64","points":[{"value":{"int64Value":"-1"}}]}]}"#] {
            XCTAssertThrowsError(try VertexTokenMonitoring.parsePage(Data(body.utf8), config: cfg), body)
        }
    }

    func testManualEntryPreserved() {
        XCTAssertEqual(Catalog.service("vertex-token-monitoring")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-101" })
    }
}
