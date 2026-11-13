import Foundation
import XCTest
@testable import CooltimeCore

final class ContinueLocalUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSumsSessionUsageWithoutReadingConversation() throws {
        let sessions = [
            Data("{\"sessionId\":\"a\",\"usage\":{\"promptTokens\":120,\"completionTokens\":30,\"totalCost\":0.04},\"history\":[{\"private\":\"text\"}]}".utf8),
            Data("{\"sessionId\":\"b\",\"usage\":{\"promptTokens\":5,\"completionTokens\":2,\"totalCost\":0.01}}".utf8)
        ]
        let snapshot = try ContinueLocalUsage.parse(sessions, fetchedAt: now)
        XCTAssertEqual(snapshot.windows[0].reportedAmount, 125)
        XCTAssertEqual(snapshot.windows[1].reportedAmount, 32)
        XCTAssertEqual(snapshot.windows[2].reportedAmount ?? 0, 0.05, accuracy: 0.000_001)
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.remainingCount == nil && $0.resetsAt == nil })
        XCTAssertNil(snapshot.credit)
        XCTAssertFalse(String(describing: snapshot).contains("private"))
    }

    func testRejectsInvalidUsage() {
        for item in ["{broken", "{}", "{\"usage\":{\"promptTokens\":true,\"completionTokens\":1,\"totalCost\":1}}",
                     "{\"usage\":{\"promptTokens\":-1,\"completionTokens\":1,\"totalCost\":1}}"] {
            XCTAssertThrowsError(try ContinueLocalUsage.parse([Data(item.utf8)], fetchedAt: now))
        }
    }

    func testManualEntryRemainsAvailable() {
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "continue-local-usage" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-25" })
    }
}
