import XCTest
@testable import CooltimeCore

final class OpenAIPlatformUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func data(_ value: String) -> Data { Data(value.utf8) }

    func testParsesHardMonthlyLimitAndOfficialCostBuckets() throws {
        let limit = data(#"{"object":"organization.spend_limit","threshold_amount":10000,"currency":"usd","interval":"month","enforcement":true}"#)
        let costs = data(#"{"object":"page","data":[{"object":"bucket","start_time":1798761600,"end_time":1798848000,"results":[{"amount":{"value":12.5,"currency":"usd"}}]},{"object":"bucket","start_time":1798848000,"end_time":1798934400,"results":[{"amount":{"value":7.25,"currency":"usd"}}]}],"has_more":false,"next_page":null}"#)
        let snapshot = try OpenAIPlatformUsage.parse(limitData: limit, costsData: costs, now: now, fetchedAt: now)
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.label, "OpenAI 組織月次ハード上限")
        XCTAssertEqual(try XCTUnwrap(window.remainingCount), 80.25, accuracy: 0.001)
        XCTAssertEqual(window.usedPercent ?? -1, 19.75, accuracy: 0.001)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reset = try XCTUnwrap(window.resetsAt)
        XCTAssertEqual(calendar.component(.month, from: reset), 2)
        XCTAssertEqual(calendar.component(.day, from: reset), 1)
    }

    func testCostsURLUsesUTCMonthStartAndCurrentInstant() {
        let url = OpenAIPlatformUsage.costsURL(now: now)
        XCTAssertTrue(url.contains("start_time=1798761600"))
        XCTAssertTrue(url.contains("end_time=1800000000"))
        XCTAssertTrue(url.contains("bucket_width=1d&limit=31"))
    }

    func testRejectsUnenforcedOrNonMonthlyCapAndMalformedCosts() {
        let costs = data(#"{"data":[],"has_more":false}"#)
        for limit in [
            #"{"threshold_amount":10000,"currency":"usd","interval":"month","enforcement":false}"#,
            #"{"threshold_amount":10000,"currency":"usd","interval":"day","enforcement":true}"#,
            #"{"threshold_amount":-1,"currency":"usd","interval":"month","enforcement":true}"#,
            #"not json"#
        ] {
            XCTAssertThrowsError(try OpenAIPlatformUsage.parse(limitData: data(limit), costsData: costs, now: now, fetchedAt: now))
        }
        let enforced = data(#"{"threshold_amount":10000,"currency":"usd","interval":"month","enforcement":true}"#)
        for invalid in [
            #"{"data":[],"has_more":true}"#,
            #"{"data":[{"results":[{"amount":{"value":1,"currency":"EUR"}}]}],"has_more":false}"#,
            #"{"data":[{"results":[{"amount":{"value":-1,"currency":"usd"}}]}],"has_more":false}"#,
            "not json"
        ] {
            XCTAssertThrowsError(try OpenAIPlatformUsage.parse(limitData: enforced, costsData: data(invalid), now: now, fetchedAt: now))
        }
    }
}
