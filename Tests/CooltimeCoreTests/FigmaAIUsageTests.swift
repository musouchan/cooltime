import XCTest
@testable import CooltimeCore

final class FigmaAIUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!
    private var period: DailyUsagePeriod { .previousSevenDays(now: now, lagHours: 6) }
    private func row(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = ["plan_id": "p1", "user_id": "u1", "user_email": "a+test@example.com",
            "day": "2026-11-05", "editor_type": "make", "seat_credits_sum": 12.5, "plan_credits_sum": 3,
            "workspace_id": "w1", "team_id": "t1", "license_group_id": NSNull()]
        overrides.forEach { result[$0.key] = $0.value }
        return result
    }
    private func page(_ rows: [[String: Any]], more: Bool = false, cursor: String? = nil) throws -> Data {
        var result: [String: Any] = ["rows": rows, "has_next_page": more]
        if let cursor { result["next_cursor"] = cursor }
        return try JSONSerialization.data(withJSONObject: result)
    }
    func testPaginatesAndKeepsUsageSeparateFromBalance() async throws {
        let pages = try [page([row()], more: true, cursor: "a+b&c"), page([row(["team_id": "t2"])])]
        var urls: [String] = []
        let snapshot = try await FigmaAIUsage.fetch(email: "a+test@example.com", period: period, fetchedAt: now) { url in
            urls.append(url)
            return pages[urls.count - 1]
        }
        XCTAssertEqual(snapshot.windows.map(\.reportedAmount), [25, 6])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.remainingCount == nil && $0.usedPercent == nil && $0.resetsAt == nil })
        XCTAssertNil(snapshot.credit)
        XCTAssertEqual(snapshot.fetchedAt, now)
        XCTAssertTrue(urls[0].contains("a%2Btest"))
        XCTAssertTrue(urls[1].contains("cursor=a%2Bb%26c"))
        XCTAssertTrue(snapshot.windows[0].label.contains("2026-10-30〜2026-11-05 UTC"))
    }
    func testExplicitZeroIsAccepted() async throws {
        let data = try page([row(["seat_credits_sum": 0, "plan_credits_sum": 0])])
        let result = try await FigmaAIUsage.fetch(email: "a+test@example.com", period: period, fetchedAt: now) { _ in data }
        XCTAssertEqual(result.windows.map(\.reportedAmount), [0, 0])
    }
    func testRejectsInvalidRowsAndAmbiguousEmptyResponse() async throws {
        var invalid = try [page([]), page([row(), row()])]
        let changes: [[String: Any]] = [["seat_credits_sum": -1], ["seat_credits_sum": "4"],
            ["seat_credits_sum": 1e20], ["plan_credits_sum": NSNull()], ["user_email": "other@example.com"],
            ["day": "2026-11-06"], ["day": "2026-10-32"], ["user_id": ""]]
        for change in changes {
            invalid.append(try page([row(change)]))
        }
        invalid.append(try page([row(), row(["plan_id": "p2", "team_id": "t2"])]))
        invalid.append(Data("{}".utf8))
        for data in invalid {
            do {
                _ = try await FigmaAIUsage.fetch(email: "a+test@example.com", period: period, fetchedAt: now) { _ in data }
                XCTFail("Invalid page must not produce a snapshot")
            } catch { }
        }
    }
    func testRejectsMissingCursorAndRepeatedPages() async throws {
        for response in [try page([row()], more: true), try page([row()], more: true, cursor: "repeat")] {
            do {
                _ = try await FigmaAIUsage.fetch(email: "a+test@example.com", period: period, fetchedAt: now) { _ in response }
                XCTFail("Incomplete pagination must fail")
            } catch { }
        }
    }
    func testTransportErrorsDoNotBecomeZeroUsage() async {
        enum Denied: Error { case forbidden }
        do {
            _ = try await FigmaAIUsage.fetch(email: "a+test@example.com", period: period, fetchedAt: now) { _ in throw Denied.forbidden }
            XCTFail("Should propagate")
        } catch { XCTAssertTrue(error is Denied) }
    }
    func testConfigurationAndUTCLagBoundary() throws {
        XCTAssertEqual(try FigmaAIUsage.configuration(from: "a+test@example.com|token").email, "a+test@example.com")
        for input in ["@example.com|key", "a@|key", "a@example.com|", "a@example.com|x\ny", "a|key|extra"] {
            XCTAssertThrowsError(try FigmaAIUsage.configuration(from: input))
        }
        let early = ISO8601DateFormatter().date(from: "2026-11-06T05:59:59Z")!
        XCTAssertEqual(DailyUsagePeriod.previousSevenDays(now: early, lagHours: 6).lastDay, "2026-11-04")
        XCTAssertEqual(period.lastDay, "2026-11-05")
        XCTAssertEqual(Catalog.service("sheet-37")?.method, .manual)
        XCTAssertEqual(Catalog.service("figma-ai-usage")?.method, .apiKey)
    }
}
