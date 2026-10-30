import XCTest
@testable import CooltimeCore

final class FormattingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMinutes() {
        XCTAssertEqual(formatRemaining(until: now.addingTimeInterval(43 * 60), now: now), "あと43分")
        XCTAssertEqual(formatRemaining(until: now.addingTimeInterval(10), now: now), "あと1分")
    }
    func testHours() {
        XCTAssertEqual(formatRemaining(until: now.addingTimeInterval((2 * 60 + 13) * 60), now: now), "あと2時間13分")
        XCTAssertEqual(formatRemaining(until: now.addingTimeInterval(3 * 3600), now: now), "あと3時間")
    }
    func testDays() {
        XCTAssertEqual(formatRemaining(until: now.addingTimeInterval((2 * 24 + 5) * 3600), now: now), "あと2日5時間")
        XCTAssertEqual(formatRemaining(until: now.addingTimeInterval(12 * 24 * 3600), now: now), "あと12日")
    }
    func testClockUsesGivenTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let d = Date(timeIntervalSince1970: 1_800_000_000)
        let later = d.addingTimeInterval(3600)
        XCTAssertEqual(formatClock(later, now: d, timeZone: tokyo).count, 5)
        XCTAssertTrue(formatClock(later.addingTimeInterval(86400), now: d, timeZone: tokyo).contains("/"))
    }
}

final class EvaluationTests: XCTestCase {
    let clock = FixedClock(Date(timeIntervalSince1970: 1_800_000_000))

    func snap(_ windows: [UsageWindow]) -> Snapshot { Snapshot(windows: windows, fetchedAt: clock.now) }

    func testUnset() { XCTAssertEqual(evaluate(nil, now: clock.now), .unset) }

    func testAvailable() {
        let s = snap([UsageWindow(label: "5時間枠", usedPercent: 38, resetsAt: clock.now.addingTimeInterval(100))])
        XCTAssertEqual(evaluate(s, now: clock.now), .available)
        XCTAssertEqual(availableSummary(s), "残り62%")
    }

    func testLimitedUsesLaterOfExhaustedWindows() {
        let early = clock.now.addingTimeInterval(3600), late = clock.now.addingTimeInterval(86400)
        let s = snap([UsageWindow(label: "5時間枠", usedPercent: 100, resetsAt: early),
                      UsageWindow(label: "週の枠", usedPercent: 100, resetsAt: late)])
        XCTAssertEqual(evaluate(s, now: clock.now), .limited(until: late))
    }

    func testOnlyOneExhaustedUsesThatOne() {
        let early = clock.now.addingTimeInterval(3600)
        let s = snap([UsageWindow(label: "5時間枠", usedPercent: 100, resetsAt: early),
                      UsageWindow(label: "週の枠", usedPercent: 20, resetsAt: clock.now.addingTimeInterval(86400))])
        XCTAssertEqual(evaluate(s, now: clock.now), .limited(until: early))
    }

    /// 時間が過ぎても「戻った」と決めない。時計を進めても、再取得するまで使用可能にならない。
    func testPastResetBecomesStaleNotAvailable() {
        let reset = clock.now.addingTimeInterval(600)
        let s = snap([UsageWindow(label: "5時間枠", usedPercent: 100, resetsAt: reset)])
        XCTAssertEqual(evaluate(s, now: clock.now), .limited(until: reset))
        clock.advance(by: 601)
        XCTAssertEqual(evaluate(s, now: clock.now), .stale(since: reset))
    }

    func testCountExhausted() {
        let s = snap([UsageWindow(label: "月のクレジット", remainingCount: 0, resetsAt: clock.now.addingTimeInterval(60))])
        if case .limited = evaluate(s, now: clock.now) {} else { XCTFail() }
    }

    func testMenuBarPicksEarliestAndCountsOthers() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let t = clock.now
        let pick = pickForMenuBar([
            (a, .limited(until: t.addingTimeInterval(7200))),
            (b, .limited(until: t.addingTimeInterval(60))),
            (c, .stale(since: t)),
            (d, .available),
        ])
        XCTAssertEqual(pick, MenuBarPick(id: b, until: t.addingTimeInterval(60), others: 1))
    }

    func testMenuBarNilWhenNothingLimited() {
        XCTAssertNil(pickForMenuBar([(UUID(), .available), (UUID(), .stale(since: clock.now)), (UUID(), .unset)]))
    }
}

final class ParserTests: XCTestCase {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    func d(_ s: String) -> Data { s.data(using: .utf8)! }

    func testClaudeStatusline() throws {
        let s = try ClaudeStatusline.parse(d("""
        {"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":1800003600},
        "seven_day":{"used_percentage":20.5,"resets_at":1800500000}}}
        """), fetchedAt: at)
        XCTAssertEqual(s.windows.count, 2)
        XCTAssertEqual(s.windows[0].resetsAt, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertTrue(s.windows[0].isExhausted)
    }

    func testClaudeStatuslineWithoutLimitsIsRejected() {
        XCTAssertThrowsError(try ClaudeStatusline.parse(d("{\"model\":{}}"), fetchedAt: at))
    }

    func testCodex() throws {
        let s = try CodexRateLimits.parse(d("""
        {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":62,"windowDurationMins":300,"resetsAt":1800003600},
        "secondary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1800400000},
        "credits":{"hasCredits":true,"unlimited":false,"balance":"12"}}}}
        """), fetchedAt: at)
        XCTAssertEqual(s.windows.map(\.label), ["5時間枠", "週の枠"])
        XCTAssertEqual(s.credit?.amount, 12)
    }

    func testElevenLabs() throws {
        let s = try ElevenLabs.parse(d("""
        {"character_count":590,"character_limit":1000,"next_character_count_reset_unix":1800100000}
        """), fetchedAt: at)
        XCTAssertEqual(s.windows[0].remainingPercent ?? 0, 41, accuracy: 0.001)
    }

    func testFirecrawl() throws {
        let s = try Firecrawl.parse(d("""
        {"success":true,"data":{"remainingCredits":820,"planCredits":3000,"billingPeriodEnd":"2026-11-01T00:00:00.000Z"}}
        """), fetchedAt: at)
        XCTAssertEqual(availableSummary(s), "残り820")
        XCTAssertNotNil(s.windows[0].resetsAt)
    }

    func testVercelAndDeepSeek() throws {
        XCTAssertEqual(try VercelAIGateway.parse(d("{\"balance\":\"95.50\",\"total_used\":\"4\"}"), fetchedAt: at).credit?.amount, 95.5)
        let ds = try DeepSeek.parse(d("{\"balance_infos\":[{\"currency\":\"USD\",\"total_balance\":\"12.00\"}]}"), fetchedAt: at)
        XCTAssertEqual(formatMoney(ds.credit!), "$12.00")
    }

    func testOpenRouterRequiresLimit() throws {
        XCTAssertThrowsError(try OpenRouter.parse(d("{\"data\":{\"limit\":null,\"limit_remaining\":null}}"), fetchedAt: at))
        let s = try OpenRouter.parse(d("{\"data\":{\"limit\":20,\"limit_remaining\":18.4,\"limit_reset\":\"monthly\"}}"), fetchedAt: at)
        XCTAssertEqual(s.credit?.amount, 18.4)
        XCTAssertNotNil(s.credit?.resetsAt)
    }

    func testOpenRouterResetBoundaries() {
        let base = ISO8601DateFormatter().date(from: "2026-10-30T13:00:00Z")!
        let f = ISO8601DateFormatter()
        XCTAssertEqual(f.string(from: OpenRouter.nextReset("daily", after: base)!), "2026-10-31T00:00:00Z")
        XCTAssertEqual(f.string(from: OpenRouter.nextReset("monthly", after: base)!), "2026-11-01T00:00:00Z")
        XCTAssertEqual(f.string(from: OpenRouter.nextReset("weekly", after: base)!), "2026-11-02T00:00:00Z")
    }
}
