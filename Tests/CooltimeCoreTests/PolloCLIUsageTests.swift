import XCTest
@testable import CooltimeCore

final class PolloCLIUsageTests: XCTestCase {
    private let observed = Date(timeIntervalSince1970: 1_793_880_000)

    func testReportedBalanceKeepsZeroAndFractionalValues() throws {
        for (json, amount) in [(#"{"availableCredits":0}"#, 0.0), (#"{"availableCredits":2.5,"user":{"email":"sample@example.com"}}"#, 2.5)] {
            let snapshot = try PolloCLIUsage.parse(Data(json.utf8), fetchedAt: observed)
            XCTAssertEqual(snapshot.credit, CreditBalance(amount: amount, currency: "credits", note: "CLIの選択中プロフィール"))
            XCTAssertEqual(snapshot.fetchedAt, observed)
            XCTAssertTrue(snapshot.windows.isEmpty)
        }
    }

    func testInvalidOrAbsentBalanceFails() {
        for json in ["invalid", "{}", #"{"availableCredits":null}"#, #"{"availableCredits":-1}"#,
                     #"{"availableCredits":true}"#, #"{"availableCredits":"2"}"#, #"{"availableCredits":9007199254740992}"#] {
            XCTAssertThrowsError(try PolloCLIUsage.parse(Data(json.utf8), fetchedAt: observed), json)
        }
    }
}
