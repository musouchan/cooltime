import XCTest
@testable import CooltimeCore

final class AnthropicUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func data(_ value: String) -> Data { Data(value.utf8) }

    func testParsesOfficialCostRowsWithoutCallingSpendBalance() throws {
        let fixture = #"{"data_refreshed_at":"2027-01-15T08:00:00Z","data":[{"starting_at":"2027-01-01T00:00:00Z","ending_at":"2027-01-02T00:00:00Z","cost":{"amount":"123.450000","currency":"USD","list_amount":"130.00","requests":3},"group":{}},{"starting_at":"2027-01-02T00:00:00Z","ending_at":"2027-01-03T00:00:00Z","cost":{"amount":"76.550000","currency":"USD","list_amount":"80.00","requests":2},"group":{}}],"has_more":false,"next_page":null}"#
        let snapshot = try AnthropicUsage.parse(data(fixture))
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.reportedAmount ?? -1, 2, accuracy: 0.0001)
        XCTAssertEqual(window.reportedUnit, "USD")
        XCTAssertNil(window.usedPercent)
        XCTAssertNil(window.remainingCount)
        XCTAssertNil(window.resetsAt)
        XCTAssertEqual(snapshot.fetchedAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testCostsURLCoversCurrentUTCMonth() {
        let value = AnthropicUsage.costsURL(now: now)
        XCTAssertTrue(value.contains("starting_at=2027-01-01T00%3A00%3A00Z"))
        XCTAssertTrue(value.contains("ending_at=2027-01-15T08%3A00%3A00Z"))
    }

    func testRejectsUnavailableRefreshMalformedAmountsAndPagination() {
        let badFixtures = [
            #"{"data_refreshed_at":null,"data":[],"has_more":false}"#,
            #"{"data_refreshed_at":"2027-01-15T08:00:00Z","data":[{"cost":{"amount":"bad","currency":"USD"}}],"has_more":false}"#,
            #"{"data_refreshed_at":"2027-01-15T08:00:00Z","data":[{"cost":{"amount":"1.00","currency":"EUR"}}],"has_more":false}"#,
            #"{"data_refreshed_at":"2027-01-15T08:00:00Z","data":[],"has_more":true,"next_page":"next"}"#,
            "not json"
        ]
        for fixture in badFixtures {
            XCTAssertThrowsError(try AnthropicUsage.parse(data(fixture)))
        }
    }
}
