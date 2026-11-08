import XCTest
@testable import CooltimeCore

final class YouAccountBalanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 0)
    private func fixture(_ balance: String, type: String = "account", id: String = "account-a") -> Data {
        Data("{\"data\":{\"type\":\"\(type)\",\"id\":\"\(id)\",\"attributes\":{\"balance\":\(balance)}}}".utf8)
    }
    func testConvertsPublishedFractionalCentsWithoutTruncation() throws {
        let s = try YouAccountBalance.parse(fixture("718924.5"), fetchedAt: now)
        XCTAssertEqual(s.credit!.amount, 7189.245, accuracy: 0.000001)
        XCTAssertEqual(s.credit?.currency, "USD")
        XCTAssertEqual(s.fetchedAt, now)
        XCTAssertNil(s.credit?.resetsAt)
    }
    func testExplicitZeroIsValid() throws {
        XCTAssertEqual(try YouAccountBalance.parse(fixture("0"), fetchedAt: now).credit?.amount, 0)
    }
    func testRejectsInvalidNumericValues() {
        for balance in ["-1", "null", "true", "\"10\"", "1e999", "9007199254740992"] {
            XCTAssertThrowsError(try YouAccountBalance.parse(fixture(balance), fetchedAt: now), balance)
        }
    }
    func testRejectsMissingFieldsAndErrorBodies() {
        for text in ["{}", "{\"data\":null}", "{\"data\":{\"type\":\"account\",\"id\":\"a\",\"attributes\":{}}}", "{\"error\":\"unauthorized\"}", "<html>error</html>"] {
            XCTAssertThrowsError(try YouAccountBalance.parse(Data(text.utf8), fetchedAt: now))
        }
    }
    func testRejectsDifferentResourceAndMissingIdentity() {
        XCTAssertThrowsError(try YouAccountBalance.parse(fixture("1", type: "key"), fetchedAt: now))
        XCTAssertThrowsError(try YouAccountBalance.parse(fixture("1", id: " "), fetchedAt: now))
    }
    func testSeparateAutomaticAndManualEntries() {
        XCTAssertEqual(Catalog.service("you-api-balance")?.method, .apiKey)
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-84" })
    }
}
