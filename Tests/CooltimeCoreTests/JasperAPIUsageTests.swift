import XCTest
@testable import CooltimeCore

final class JasperAPIUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")!
    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testBuildsPreviousCompleteSevenUTCDateRange() {
        let period = JasperAPIUsage.previousSevenDays(now: now)
        XCTAssertEqual(period.start, ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
        XCTAssertEqual(period.end, ISO8601DateFormatter().date(from: "2026-11-08T00:00:00Z"))
        let components = URLComponents(string: JasperAPIUsage.url(period: period))!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(components.host, "api.jasper.ai")
        XCTAssertEqual(components.path, "/v1/usage")
        XCTAssertEqual(items["granularity"], "day")
        XCTAssertEqual(items["start"], "2026-11-01T00:00:00.000Z")
        XCTAssertEqual(items["end"], "2026-11-08T00:00:00.000Z")
    }

    func testSumsPublishedRequestBuckets() throws {
        let period = JasperAPIUsage.previousSevenDays(now: now)
        let fixture = #"""
        {"requestId":"req-1","resource":"usage","data":{"requests":[
          {"t":"2026-11-01T00:00:00.000Z","v":83},
          {"t":"2026-11-02T00:00:00Z","v":17.5}
        ]}}
        """#
        let snapshot = try JasperAPIUsage.parse(data(fixture), period: period, fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 100.5)
        XCTAssertEqual(snapshot.windows.first?.reportedUnit, "requests")
        XCTAssertNil(snapshot.windows.first?.remainingCount)
        XCTAssertNil(snapshot.windows.first?.resetsAt)
        XCTAssertNil(snapshot.credit)
    }

    func testEmptyCompleteReportIsExplicitZero() throws {
        let period = JasperAPIUsage.previousSevenDays(now: now)
        let snapshot = try JasperAPIUsage.parse(
            data(#"{"requestId":"req-1","resource":"usage","data":{"requests":[]}}"#),
            period: period, fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 0)
    }

    func testRejectsMalformedDuplicateOutOfRangeAndNegativeUsage() {
        let period = JasperAPIUsage.previousSevenDays(now: now)
        for fixture in [
            "{}",
            #"{"requestId":"","resource":"usage","data":{"requests":[]}}"#,
            #"{"requestId":"x","resource":"content","data":{"requests":[]}}"#,
            #"{"requestId":"x","resource":"usage","data":{"requests":[{"t":"2026-11-01T00:00:00Z","v":1},{"t":"2026-11-01T00:00:00Z","v":2}]}}"#,
            #"{"requestId":"x","resource":"usage","data":{"requests":[{"t":"2026-11-08T00:00:00Z","v":1}]}}"#,
            #"{"requestId":"x","resource":"usage","data":{"requests":[{"t":"2026-11-01T00:00:00Z","v":-1}]}}"#,
            "<html>error</html>"
        ] {
            XCTAssertThrowsError(try JasperAPIUsage.parse(data(fixture), period: period,
                                                          fetchedAt: now), fixture)
        }
    }

    func testKeepsManualEntry() {
        XCTAssertEqual(Catalog.service("jasper-api-usage")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-126" })
    }
}
