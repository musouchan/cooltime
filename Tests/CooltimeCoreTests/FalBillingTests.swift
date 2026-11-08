import XCTest
@testable import CooltimeCore

final class FalBillingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 0)

    func testReadsAccountBalanceAndCurrency() throws {
        let data = Data(#"{"username":"demo-team","credits":{"current_balance":24.5,"currency":"USD"}}"#.utf8)
        let zero = Data(#"{"credits":{"current_balance":0,"currency":"EUR"}}"#.utf8)
        XCTAssertEqual(try FalBilling.parse(data, fetchedAt: now),
                       Snapshot(credit: CreditBalance(amount: 24.5, currency: "USD"), fetchedAt: now))
        XCTAssertEqual(try FalBilling.parse(zero, fetchedAt: now),
                       Snapshot(credit: CreditBalance(amount: 0, currency: "EUR"), fetchedAt: now))
    }

    func testRejectsMissingAndInvalidBalanceOrCurrency() {
        for json in ["{}", #"{"credits":{"current_balance":-1,"currency":"USD"}}"#,
                     #"{"credits":{"current_balance":"1","currency":"USD"}}"#,
                     #"{"credits":{"current_balance":1,"currency":"?"}}"#,
                     #"{"credits":{"current_balance":1}}"#] {
            XCTAssertThrowsError(try FalBilling.parse(Data(json.utf8), fetchedAt: now), json)
        }
    }
}
