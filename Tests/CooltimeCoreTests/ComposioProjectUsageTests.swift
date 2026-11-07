import XCTest
@testable import CooltimeCore

final class ComposioProjectUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-08T16:20:00Z")!

    func testRequestUsesPreviousSevenCompleteUTCDays() throws {
        let body = try ComposioProjectUsage.requestBody(now: now)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Int64])
        XCTAssertEqual(object["from"], 1_793_491_200_000) // 2026-11-01 UTC
        XCTAssertEqual(object["to"]! - object["from"]!, 7 * 86_400_000)
    }

    func testReadsEntityQuantityWithoutTreatingItAsBalance() throws {
        let data = Data(#"{"entities":{"tool_call":{"unit":"calls","total_quantity":"123.5","event_count":4}},"instant_charge":"0.01"}"#.utf8)
        let snapshot = try ComposioProjectUsage.parse(data, fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 123.5)
        XCTAssertEqual(snapshot.windows.first?.reportedUnit, "calls")
        XCTAssertNil(snapshot.windows.first?.remainingCount)
        XCTAssertNil(snapshot.windows.first?.resetsAt)
        XCTAssertNil(snapshot.credit)
    }

    func testRejectsMalformedNegativeAndMissingMetering() {
        for string in ["{}", #"{"entities":{}}"#,
                       #"{"entities":{"x":{"unit":"calls","total_quantity":"-3","event_count":2}}}"#,
                       #"{"entities":{"x":{"unit":"calls","total_quantity":"NaN","event_count":2}}}"#,
                       #"{"entities":{"x":{"unit":"calls","total_quantity":"3","event_count":-1}}}"#,
                       "<html>failure</html>"] {
            XCTAssertThrowsError(try ComposioProjectUsage.parse(Data(string.utf8), fetchedAt: now), string)
        }
    }

    func testManualEntryStillAvailable() {
        XCTAssertEqual(Catalog.service("composio-project-usage")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-111" })
    }
}
