import XCTest
@testable import CooltimeCore

final class IntercomFinConversationsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")!

    func testSearchesFinParticipationInCompleteUTCWeekWithoutPreview() throws {
        let period = IntercomFinConversations.period(now: now)
        let body = try JSONSerialization.jsonObject(with: IntercomFinConversations.requestBody(period: period)) as! [String: Any]
        let query = body["query"] as! [String: Any]
        let filters = query["value"] as! [[String: Any]]
        XCTAssertEqual((body["pagination"] as! [String: Int])["per_page"], 1)
        XCTAssertEqual(filters.count, 5)
        XCTAssertEqual(filters[0]["value"] as? Int, Int(period.start.timeIntervalSince1970))
        XCTAssertEqual(filters[1]["value"] as? Int, Int(period.end.timeIntervalSince1970) - 1)
        XCTAssertEqual(filters[2]["field"] as? String, "ai_agent_participated")
        XCTAssertEqual(filters[3]["value"] as? String, "fin_preview")
        XCTAssertEqual(filters[4]["value"] as? String, "workflow_preview")
    }

    func testCountIsOnlyReportedUsage() throws {
        let json = #"{"type":"conversation.list","total_count":42,"conversations":[{"id":"conv-1"}]}"#
        let result = try IntercomFinConversations.parse(Data(json.utf8), fetchedAt: now)
        XCTAssertEqual(result.windows.first?.reportedAmount, 42)
        XCTAssertNil(result.windows.first?.remainingCount)
        XCTAssertNil(result.windows.first?.resetsAt)
        XCTAssertNil(result.credit)
    }

    func testRejectsPartialOrInvalidSearchResults() {
        for json in ["{}", "<html>no</html>",
                     #"{"type":"list","total_count":2,"conversations":[]}"#,
                     #"{"type":"conversation.list","total_count":-1,"conversations":[]}"#,
                     #"{"type":"conversation.list","total_count":0,"conversations":[{"id":"x"},{"id":"y"}]}"#] {
            XCTAssertThrowsError(try IntercomFinConversations.parse(Data(json.utf8), fetchedAt: now))
        }
    }

    func testCatalogKeepsOriginalManualService() {
        XCTAssertEqual(Catalog.service("intercom-fin-conversations")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-128" })
    }
}
