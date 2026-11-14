import Foundation
import XCTest
@testable import CooltimeCore

final class REimagineHomeMaskUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCountsUniqueDocumentedJobsWithoutInventingBalance() throws {
        let log = """
        {"status":"success","data":{"job_id":"job-1","credits_consumed":5,"image_url":"private"}}
        {"status":"success","data":{"job_id":"job-2","credits_consumed":3}}
        {"status":"success","data":{"job_id":"job-1","credits_consumed":5}}
        """
        let snapshot = try REimagineHomeMaskUsage.parse(Data(log.utf8), fetchedAt: now)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].reportedAmount, 8)
        XCTAssertEqual(snapshot.windows[0].reportedUnit, "credits")
        XCTAssertNil(snapshot.credit)
        XCTAssertNil(snapshot.windows[0].remainingCount)
        XCTAssertNil(snapshot.windows[0].resetsAt)
        XCTAssertNil(snapshot.windows[0].usedPercent)
        XCTAssertFalse(String(describing: snapshot).contains("private"))
    }

    func testRejectsMalformedAmbiguousOrUnmeteredResponses() {
        for log in ["{}", "{broken", "{\"status\":\"error\",\"data\":{\"job_id\":\"1\",\"credits_consumed\":5}}",
                    "{\"status\":\"success\",\"data\":{\"job_id\":\"1\",\"credits_consumed\":true}}",
                    "{\"status\":\"success\",\"data\":{\"job_id\":\"1\",\"credits_consumed\":-1}}",
                    "{\"status\":\"success\",\"data\":{\"job_id\":\"1\"}}",
                    "{\"status\":\"success\",\"data\":{\"job_id\":\"1\",\"credits_consumed\":2}}\n{\"status\":\"success\",\"data\":{\"job_id\":\"1\",\"credits_consumed\":3}}"] {
            XCTAssertThrowsError(try REimagineHomeMaskUsage.parse(Data(log.utf8), fetchedAt: now))
        }
    }

    func testManualEntryRemainsAvailable() {
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "reimaginehome-mask-usage" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-161" })
    }
}
