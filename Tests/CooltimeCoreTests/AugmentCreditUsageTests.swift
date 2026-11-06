import XCTest
@testable import CooltimeCore

final class AugmentCreditUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!
    private var period: DailyUsagePeriod { .previousSevenDays(now: now, lagHours: 2) }
    private func page(_ rows: [[String: Any]], more: Bool = false, cursor: String? = nil,
                      metadata: [String: Any] = [:]) throws -> Data {
        var meta: [String: Any] = ["effective_start_date": "2026-10-30", "effective_end_date": "2026-11-05",
            "generated_at": "2026-11-06T11:00:00Z", "returned_record_count": rows.count]
        metadata.forEach { meta[$0.key] = $0.value }
        var pagination: [String: Any] = ["has_more": more]
        if let cursor { pagination["next_cursor"] = cursor }
        return try JSONSerialization.data(withJSONObject: ["records": rows, "pagination": pagination, "metadata": meta])
    }
    func testFindsOnlySelectedUserAcrossPages() async throws {
        let pages = try [page([["user_email": "other@example.com", "credits_consumed": 100],
                               ["service_account_name": "ci", "credits_consumed": 200]], more: true, cursor: "a+b"),
                         page([["user_email": "A@example.com", "credits_consumed": 42]])]
        var urls: [String] = []
        let result = try await AugmentCreditUsage.fetch(email: "a@example.com", period: period, fetchedAt: now) { url in
            urls.append(url)
            return pages[urls.count - 1]
        }
        XCTAssertEqual(result.windows.first?.reportedAmount, 42)
        XCTAssertEqual(result.windows.first?.reportedUnit, "credits")
        XCTAssertNil(result.windows.first?.remainingCount)
        XCTAssertNil(result.windows.first?.resetsAt)
        XCTAssertNil(result.windows.first?.usedPercent)
        XCTAssertNil(result.credit)
        XCTAssertTrue(urls[1].contains("cursor=a%2Bb"))
        XCTAssertTrue(urls[0].contains("by_date=false"))
        XCTAssertFalse(urls[0].contains("a@example.com"))
    }
    func testExplicitZero() async throws {
        let data = try page([["user_email": "a@example.com", "credits_consumed": 0]])
        let result = try await AugmentCreditUsage.fetch(email: "a@example.com", period: period, fetchedAt: now) { _ in data }
        XCTAssertEqual(result.windows.first?.reportedAmount, 0)
    }
    func testInvalidAmountIdentityAndDimensionFail() async throws {
        let records: [[String: Any]] = [["user_email": "a@example.com", "credits_consumed": -1],
            ["user_email": "a@example.com", "credits_consumed": "2"],
            ["user_email": "a@example.com", "credits_consumed": 1.5],
            ["user_email": "a@example.com", "credits_consumed": 1e20],
            ["credits_consumed": 1], ["user_email": "a@example.com", "service_account_name": "ci", "credits_consumed": 1],
            ["user_email": "a@example.com", "credits_consumed": 1, "date": "2026-11-05"]]
        for row in records { await assertFails(try page([row])) }
        await assertFails(try page([]))
        await assertFails(try page([["user_email": "other@example.com", "credits_consumed": 12]]))
        let duplicate: [String: Any] = ["user_email": "a@example.com", "credits_consumed": 12]
        await assertFails(try page([duplicate, duplicate]))
    }
    func testRejectsMismatchedPeriodMetadataAndIncompletePages() async throws {
        let rows: [[String: Any]] = [["user_email": "a@example.com", "credits_consumed": 12]]
        let changes: [[String: Any]] = [["effective_start_date": "2026-11-01"], ["effective_end_date": "2026-11-06"],
            ["returned_record_count": 2], ["generated_at": "bad"], ["generated_at": "2099-01-01T00:00:00Z"]]
        for change in changes { await assertFails(try page(rows, metadata: change)) }
        await assertFails(try page(rows, more: true))
        await assertFails(try page(rows, more: true, cursor: "same"))
        await assertFails(Data("{}".utf8))
    }
    func testPageCapAndLaterTransportFailureDiscardPartialUsage() async throws {
        var calls = 0
        do {
            _ = try await AugmentCreditUsage.fetch(email: "a@example.com", period: period, fetchedAt: now) { _ in
                calls += 1
                return try self.page([["user_email": "other@example.com", "credits_consumed": 1]], more: true, cursor: "\(calls)")
            }
            XCTFail("Page cap must fail")
        } catch { XCTAssertEqual(calls, 20) }
        calls = 0
        enum Denied: Error { case unauthorized }
        do {
            _ = try await AugmentCreditUsage.fetch(email: "a@example.com", period: period, fetchedAt: now) { _ in
                calls += 1
                if calls == 2 { throw Denied.unauthorized }
                return try self.page([["user_email": "a@example.com", "credits_consumed": 1]], more: true, cursor: "next")
            }
            XCTFail("Must not return partial success")
        } catch { XCTAssertTrue(error is Denied) }
    }
    func testConfigurationAndManualCoexistence() throws {
        XCTAssertEqual(try AugmentCreditUsage.configuration(from: "a@example.com|token").token, "token")
        XCTAssertThrowsError(try AugmentCreditUsage.configuration(from: "a@example.com|x\ry"))
        XCTAssertEqual(Catalog.service("sheet-19")?.method, .manual)
        XCTAssertEqual(Catalog.service("augment-credit-usage")?.method, .apiKey)
    }
    private func assertFails(_ data: Data, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await AugmentCreditUsage.fetch(email: "a@example.com", period: period, fetchedAt: now) { _ in data }
            XCTFail("Invalid data must fail", file: file, line: line)
        } catch { }
    }
}
