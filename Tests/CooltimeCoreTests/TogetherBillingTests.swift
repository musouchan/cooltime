import XCTest
@testable import CooltimeCore

final class TogetherBillingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testBuildsCurrentUTCMonthURL() {
        let url = TogetherBilling.usageURL(now: now)
        XCTAssertTrue(url.contains("month=2027-01"))
        XCTAssertTrue(url.contains("granularity=day"))
        XCTAssertTrue(url.contains("limit=1000"))
    }

    func testSumsOfficialUSDLineItemCosts() throws {
        let fixture = #"{"object":"list","organization_id":"org-1","billing_period":"2027-01","currency":"USD","latest_window_end":"2027-01-15T00:00:00Z","data":[{"date":"2027-01-14","line_items":[{"product_name":"Model A","quantity":"10","unit_price":"0.1","cost":"1.2500"},{"product_name":"Model B","quantity":"2","unit_price":"0.3","cost":"0.6000"}]},{"date":"2027-01-15","line_items":[{"product_name":"Model A","quantity":"1","unit_price":"0.1","cost":"0.1500"}]}],"next_cursor":null}"#
        let snapshot = try TogetherBilling.parse(data(fixture), expectedMonth: "2027-01", fetchedAt: now)
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.reportedAmount ?? -1, 2, accuracy: 0.0001)
        XCTAssertEqual(window.reportedUnit, "USD")
        XCTAssertNil(window.usedPercent)
        XCTAssertNil(window.remainingCount)
        XCTAssertNil(window.resetsAt)
    }

    func testAllowsZeroUsageMonth() throws {
        let fixture = #"{"object":"list","organization_id":"org-1","billing_period":"2027-01","currency":"USD","data":[],"next_cursor":null}"#
        let snapshot = try TogetherBilling.parse(data(fixture), expectedMonth: "2027-01", fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 0)
    }

    func testRejectsWrongMonthCurrencyMalformedCostAndPartialPages() {
        let fixtures = [
            #"{"object":"list","billing_period":"2026-12","currency":"USD","data":[],"next_cursor":null}"#,
            #"{"object":"list","billing_period":"2027-01","currency":"EUR","data":[],"next_cursor":null}"#,
            #"{"object":"list","billing_period":"2027-01","currency":"USD","data":[{"line_items":[{"cost":"NaN"}]}],"next_cursor":null}"#,
            #"{"object":"list","billing_period":"2027-01","currency":"USD","data":[],"next_cursor":"cursor"}"#,
            "not json"
        ]
        for fixture in fixtures {
            XCTAssertThrowsError(try TogetherBilling.parse(data(fixture), expectedMonth: "2027-01", fetchedAt: now))
        }
    }
}
