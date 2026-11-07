import Foundation
import XCTest
@testable import CooltimeCore

final class GeminiAPIRequestUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-07T10:00:00Z")!
    private let project = "sample-project"

    func testRequestScopePaginationAndReportedAmount() async throws {
        let period = GeminiAPIRequestUsage.period(now: now)
        var pages = [
            page(day: "2026-11-02", count: "25", next: "page+/="),
            page(day: "2026-11-03", count: "12")
        ]
        let snapshot = try await GeminiAPIRequestUsage.fetch(projectID: project, period: period, fetchedAt: now) { url in
            let components = try XCTUnwrap(URLComponents(string: url))
            XCTAssertEqual(components.host, "monitoring.googleapis.com")
            XCTAssertEqual(components.path, "/v3/projects/sample-project/timeSeries")
            let items = try XCTUnwrap(components.queryItems)
            let filter = try XCTUnwrap(items.first { $0.name == "filter" }?.value)
            XCTAssertTrue(filter.contains("resource.labels.service = \"generativelanguage.googleapis.com\""))
            XCTAssertTrue(filter.contains("resource.labels.project_id = \"sample-project\""))
            XCTAssertTrue(filter.contains("serviceruntime.googleapis.com/api/request_count"))
            XCTAssertTrue(items.contains(URLQueryItem(name: "aggregation.crossSeriesReducer", value: "REDUCE_SUM")))
            XCTAssertEqual(items.first { $0.name == "interval.startTime" }?.value, "2026-10-31T00:00:00Z")
            XCTAssertEqual(items.first { $0.name == "interval.endTime" }?.value, "2026-11-07T00:00:00Z")
            XCTAssertEqual(items.first { $0.name == "pageToken" }?.value, pages.count == 2 ? nil : "page+/=")
            if pages.count == 1 { XCTAssertTrue(url.contains("page%2B")) }
            return pages.removeFirst()
        }
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 37)
        XCTAssertNil(snapshot.windows.first?.remainingCount)
        XCTAssertNil(snapshot.windows.first?.resetsAt)
    }

    func testMissingMalformedOrPartialMetricsAreNotReported() async throws {
        let period = GeminiAPIRequestUsage.period(now: now)
        for data in [Data("{}".utf8), Data(#"{"executionErrors":[{"code":13}]}"#.utf8),
                     page(day: "2026-11-02", count: "-1"),
                     page(day: "2026-11-02", count: "10", project: "other-project"),
                     page(day: "2026-11-08", count: "10"),
                     page(day: "2026-11-02", count: "10", next: "same")] {
            do {
                _ = try await GeminiAPIRequestUsage.fetch(projectID: project, period: period, fetchedAt: now) { _ in data }
                XCTFail("Expected invalid or incomplete metrics to fail")
            } catch is ParseError {}
        }
    }

    func testFailedSecondPageDoesNotProducePartialSnapshot() async throws {
        enum Transport: Error { case unauthorized }
        let period = GeminiAPIRequestUsage.period(now: now)
        do {
            _ = try await GeminiAPIRequestUsage.fetch(projectID: project, period: period, fetchedAt: now) { url in
                if url.contains("pageToken=") { throw Transport.unauthorized }
                return self.page(day: "2026-11-02", count: "5", next: "second")
            }
            XCTFail("Expected second-page failure")
        } catch Transport.unauthorized {}
    }

    func testProjectValidationAndManualCatalogCompatibility() {
        for input in ["other/project", "example\" AND", "0123456", "sample-project-"] {
            XCTAssertThrowsError(try GeminiAPIRequestUsage.projectID(from: input))
        }
        XCTAssertEqual(Catalog.service("sheet-88")?.method, .manual)
        XCTAssertEqual(Catalog.service("gemini-api-request-usage")?.method, .apiKey)
    }

    private func page(day: String, count: String, project: String? = nil, next: String? = nil) -> Data {
        let token = next.map { ",\"nextPageToken\":\"\($0)\"" } ?? ""
        return Data("""
        {"timeSeries":[{
          "metric":{"type":"serviceruntime.googleapis.com/api/request_count"},
          "resource":{"type":"consumed_api","labels":{"project_id":"\(project ?? self.project)","service":"generativelanguage.googleapis.com"}},
          "valueType":"INT64",
          "points":[{"interval":{"endTime":"\(day)T00:00:00Z"},"value":{"int64Value":"\(count)"}}]
        }]\(token)}
        """.utf8)
    }
}
