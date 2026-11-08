import XCTest
@testable import CooltimeCore

final class AdaResolutionUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")!
    private var config: AdaResolutionUsage.Configuration {
        get throws { try AdaResolutionUsage.configuration(from: "example|fixture-token") }
    }

    func testUsesOfficialExportOnPreviousCompleteUTCDay() throws {
        let config = try self.config
        let url = try XCTUnwrap(URLComponents(string: AdaResolutionUsage.initialURL(config: config, day: AdaResolutionUsage.previousDay(now: now))))
        XCTAssertEqual(url.host, "example.ada.support")
        XCTAssertEqual(url.path, "/api/v2/export/conversations")
        XCTAssertEqual(url.queryItems?.first { $0.name == "created_since" }?.value, "2026-11-07T00:00:00Z")
        XCTAssertEqual(url.queryItems?.first { $0.name == "created_to" }?.value, "2026-11-08T00:00:00Z")
        XCTAssertEqual(url.queryItems?.first { $0.name == "page_size" }?.value, "100")
    }

    func testPaginatesAndCountsOnlyExplicitNonTestResolutions() async throws {
        let config = try self.config
        var urls = [String]()
        let result = try await AdaResolutionUsage.fetch(config: config, now: now) { url in
            urls.append(url)
            return urls.count == 1
                ? Data(#"{"data":[{"_id":"a","automated_resolution_classification":"Resolved","is_test_user":false},{"_id":"b","automated_resolution_classification":"Resolved","is_test_user":true}],"meta":{"next_page_uri":"/api/v2/export/conversations?created_since=2026-11-07T01%3A00%3A00Z&created_to=2026-11-08T00%3A00%3A00Z&page_size=100"}}"#.utf8)
                : Data(#"{"data":[{"_id":"c","automated_resolution_classification":"Not Resolved","is_test_user":false},{"_id":"d","automated_resolution_classification":"Resolved","is_test_user":false}],"meta":{}}"#.utf8)
        }
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(result.windows.first?.reportedAmount, 2)
        XCTAssertNil(result.windows.first?.remainingCount)
        XCTAssertNil(result.credit)
    }

    func testEmptyReportIsZeroAndRejectsIncompleteOrUnsafePages() async throws {
        let config = try self.config
        let empty = try await AdaResolutionUsage.fetch(config: config, now: now) { _ in Data(#"{"data":[],"meta":{}}"#.utf8) }
        XCTAssertEqual(empty.windows.first?.reportedAmount, 0)
        for json in ["{}", #"{"data":[{"_id":"a","is_test_user":false}],"meta":{}}"#,
                     #"{"data":[{"_id":"a","automated_resolution_classification":"Resolved","is_test_user":false},{"_id":"a","automated_resolution_classification":"Resolved","is_test_user":false}]}"#,
                     #"{"data":[],"meta":{"next_page_uri":"https://evil.example/api/v2/export/conversations?created_since=x&created_to=x"}}"#] {
            do {
                _ = try await AdaResolutionUsage.fetch(config: config, now: now) { _ in Data(json.utf8) }
                XCTFail("Invalid report produced a snapshot")
            } catch is ParseError { }
        }
    }

    func testRejectsUnsafeConfigurationAndKeepsManualEntry() {
        for input in ["../other|token", "other.ada.support|token", "example|token\r\ninjection", "example|"] {
            XCTAssertThrowsError(try AdaResolutionUsage.configuration(from: input))
        }
        XCTAssertEqual(Catalog.service("sheet-130")?.method, .manual)
        XCTAssertEqual(Catalog.service("ada-resolution-usage")?.method, .apiKey)
    }
}
