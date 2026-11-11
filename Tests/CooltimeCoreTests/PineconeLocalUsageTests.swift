import Foundation
import XCTest
@testable import CooltimeCore

final class PineconeLocalUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSumsOnlyCapturedUsageWithoutInventingBalance() throws {
        let log = """
        {"usage":{"read_units":2},"vectors":[{"id":"private"}]}
        {"usage":{"read_units":3,"write_units":4}}
        """
        let snapshot = try PineconeLocalUsage.parse(Data(log.utf8), fetchedAt: now)
        XCTAssertEqual(snapshot.windows[0].reportedAmount, 5)
        XCTAssertEqual(snapshot.windows[1].reportedAmount, 4)
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.remainingCount == nil && $0.resetsAt == nil && $0.usedPercent == nil })
        XCTAssertNil(snapshot.credit)
        XCTAssertFalse(String(describing: snapshot).contains("private"))
    }

    func testRejectsMalformedAndNonUsageInput() {
        for log in ["{}", "{broken", "{\"usage\":{\"read_units\":true}}", "{\"usage\":{\"read_units\":-1}}"] {
            XCTAssertThrowsError(try PineconeLocalUsage.parse(Data(log.utf8), fetchedAt: now))
        }
    }

    func testManualEntryRemainsAvailable() {
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "pinecone-local-usage" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-117" })
    }
}
