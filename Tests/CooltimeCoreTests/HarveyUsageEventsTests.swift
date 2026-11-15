import Foundation
import XCTest
@testable import CooltimeCore

final class HarveyUsageEventsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOfficialEventSchemaCountsByAreaOnly() throws {
        let data = Data("""
        {"events":[
          {"unique_usage_id":"id-1","product_surface_area":"ASSISTANT","user":"private@example.com","workflow_name":"private"},
          {"unique_usage_id":"id-2","product_surface_area":"ASSISTANT"},
          {"unique_usage_id":"id-3","product_surface_area":"VAULT"}
        ]}
        """.utf8)
        let snapshot = try HarveyUsageEvents.parse(data, fetchedAt: now)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows.first { $0.label.contains("ASSISTANT") }?.reportedAmount, 2)
        XCTAssertEqual(snapshot.windows.first { $0.label.contains("VAULT") }?.reportedAmount, 1)
        XCTAssertNil(snapshot.credit)
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.remainingCount == nil && $0.resetsAt == nil && $0.usedPercent == nil })
        XCTAssertFalse(String(describing: snapshot).contains("private"))
    }

    func testEmptyDayIsZero() throws {
        let snapshot = try HarveyUsageEvents.parse(Data("{\"events\":[]}".utf8), fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 0)
    }

    func testRejectsDuplicateOrUnknownEvents() {
        for input in ["{}", "{\"events\":[{\"unique_usage_id\":\"a\",\"product_surface_area\":\"OTHER\"}]}",
                      "{\"events\":[{\"unique_usage_id\":\"a\",\"product_surface_area\":\"ASSISTANT\"},{\"unique_usage_id\":\"a\",\"product_surface_area\":\"VAULT\"}]}"] {
            XCTAssertThrowsError(try HarveyUsageEvents.parse(Data(input.utf8), fetchedAt: now))
        }
    }

    func testRegionAllowlistAndManualOption() throws {
        XCTAssertTrue(try HarveyUsageEvents.url(region: "EU", now: now).hasPrefix("https://eu.api.harvey.ai/api/v2/history/usage?"))
        XCTAssertThrowsError(try HarveyUsageEvents.configuration(from: "example.org|secret"))
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "harvey-usage-events" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-148" })
    }
}
