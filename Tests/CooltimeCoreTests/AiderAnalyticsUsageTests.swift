import Foundation
import XCTest
@testable import CooltimeCore

final class AiderAnalyticsUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSumsOnlyMessageEventsAndDoesNotInventBalance() throws {
        let log = """
        {"event":"message_send","properties":{"prompt_tokens":120,"completion_tokens":30,"cost":0.04,"total_cost":2.4,"prompt":"private"},"time":1790000000}
        {"event":"command_clear","properties":{},"time":1790000001}
        {"event":"message_send","properties":{"prompt_tokens":0,"completion_tokens":5,"cost":0.01,"total_cost":0.01},"time":1790000002}
        """
        let s = try AiderAnalyticsUsage.parse(Data(log.utf8), fetchedAt: now)
        XCTAssertEqual(s.windows[0].reportedAmount, 120)
        XCTAssertEqual(s.windows[1].reportedAmount, 35)
        XCTAssertEqual(s.windows[2].reportedAmount ?? 0, 0.05, accuracy: 0.000_001)
        XCTAssertTrue(s.windows.allSatisfy { $0.remainingCount == nil && $0.resetsAt == nil && $0.usedPercent == nil })
        XCTAssertNil(s.credit)
        XCTAssertFalse(String(describing: s).contains("private"))
    }

    func testRejectsMalformedOrUnmeasuredLog() {
        for log in ["{}", "{broken", "{\"event\":\"message_send\",\"properties\":{\"prompt_tokens\":1},\"time\":1790000000}",
                    "{\"event\":\"message_send\",\"properties\":{\"prompt_tokens\":true,\"completion_tokens\":0,\"cost\":0},\"time\":1790000000}"] {
            XCTAssertThrowsError(try AiderAnalyticsUsage.parse(Data(log.utf8), fetchedAt: now))
        }
    }

    func testManualEntryRemainsAvailable() {
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "aider-local-usage" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-24" })
    }
}
