import XCTest
@testable import CooltimeCore

final class BraveRateHeadersTests: XCTestCase {
    private let captured = Date(timeIntervalSince1970: 1_800_000_000)

    private func data(_ headers: String) -> Data { Data(headers.utf8) }

    func testReportsMonthlyQuotaWithoutTreatingBurstAsMonthlyOrCredit() throws {
        let headers = """
        HTTP/2 200
        X-RateLimit-Limit: 1, 15000
        X-RateLimit-Policy: 1;w=1, 15000;w=2592000
        X-RateLimit-Remaining: 0, 14523
        X-RateLimit-Reset: 1, 1234567

        """
        let snapshot = try BraveRateHeaders.parse(data(headers), capturedAt: captured,
                                                   now: captured.addingTimeInterval(10))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].remainingCount, 14523)
        XCTAssertEqual(snapshot.windows[0].usedPercent!, 100 * 477 / 15000, accuracy: 0.0001)
        XCTAssertEqual(snapshot.windows[0].resetsAt, captured.addingTimeInterval(1_234_567))
        XCTAssertNil(snapshot.credit)
        XCTAssertEqual(snapshot.fetchedAt, captured)
        XCTAssertEqual(Catalog.service("sheet-110")?.method, .manual)
        XCTAssertEqual(Catalog.service("brave-passive-quota")?.method, .apiKey)
    }

    func testRejectsExpiredUnlimitedAndMisalignedHeaders() {
        let base = """
        HTTP/2 200
        x-ratelimit-limit: 1, 15000
        x-ratelimit-policy: 1;w=1, 15000;w=2592000
        x-ratelimit-remaining: 0, 14523
        x-ratelimit-reset: 1, 100
        """
        XCTAssertThrowsError(try BraveRateHeaders.parse(data(base), capturedAt: captured,
                                                          now: captured.addingTimeInterval(101)))
        XCTAssertThrowsError(try BraveRateHeaders.parse(data(base.replacingOccurrences(of: "1, 15000\n", with: "1\n")),
                                                          capturedAt: captured, now: captured))
        XCTAssertThrowsError(try BraveRateHeaders.parse(data(base.replacingOccurrences(of: "15000", with: "0")),
                                                          capturedAt: captured, now: captured))
    }

    func testSelectsLastResponseHeadersAndRejectsInvalidNumbers() throws {
        let first = "HTTP/1.1 100 Continue\nX-RateLimit-Limit: 5\n"
        let final = "HTTP/2 200\nX-RateLimit-Limit: 10\nX-RateLimit-Policy: 10;w=2592000\nX-RateLimit-Remaining: 7\nX-RateLimit-Reset: 20\n"
        let snapshot = try BraveRateHeaders.parse(data(first + final), capturedAt: captured, now: captured)
        XCTAssertEqual(snapshot.windows.first?.remainingCount, 7)
        XCTAssertThrowsError(try BraveRateHeaders.parse(data(final.replacingOccurrences(of: "Remaining: 7", with: "Remaining: -1")),
                                                          capturedAt: captured, now: captured))
    }
}
