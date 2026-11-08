import XCTest
@testable import CooltimeCore

final class MistralAdminSpendStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_491_200)

    func testExplicitLimitReachedAndNotReached() throws {
        for reached in [true, false] {
            let data = Data("""
            {"limits":{"completion":{"monthly_limit_reached":\(reached)},"currency":"USD","last_payment_failure":false}}
            """.utf8)
            let snapshot = try MistralAdminSpendStatus.parse(data, fetchedAt: now)
            XCTAssertEqual(snapshot.windows.first?.isLimited, reached)
            XCTAssertEqual(snapshot.windows.first?.isExhausted, reached)
            XCTAssertNil(snapshot.windows.first?.remainingCount)
            XCTAssertNil(snapshot.windows.first?.usedPercent)
            XCTAssertNil(snapshot.windows.first?.resetsAt)
            XCTAssertNil(snapshot.credit)
        }
    }

    func testRejectsMissingOrAmbiguousStatus() {
        for fixture in ["{}", #"{"limits":{"completion":{}}}"#,
                        #"{"limits":{"completion":{"monthly_limit_reached":"false"}}}"#,
                        #"{"limits":{"completion":{"monthly_limit_reached":null}}}"#,
                        "<html>failure</html>"] {
            XCTAssertThrowsError(try MistralAdminSpendStatus.parse(Data(fixture.utf8), fetchedAt: now), fixture)
        }
    }

    func testManualEntryRemainsAvailable() {
        XCTAssertEqual(Catalog.service("mistral-admin-spend-status")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-89" })
    }
}
