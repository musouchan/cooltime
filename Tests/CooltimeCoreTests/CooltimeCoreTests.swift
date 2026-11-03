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

final class IdentityTests: XCTestCase {
    func d(_ s: String) -> Data { s.data(using: .utf8)! }

    func testClaudeAccountReadsOnlyEmail() {
        let id = ClaudeAccount.parse(d("""
        {"oauthAccount":{"emailAddress":"me@example.com","organizationName":"Me"},"projects":{}}
        """))
        XCTAssertEqual(id, AccountIdentity(email: "me@example.com"))
        XCTAssertNil(ClaudeAccount.parse(d("{\"projects\":{}}")))
    }

    func testCodexAccountMapsPlanToType() {
        let plus = CodexAccount.parse(d("{\"id\":3,\"result\":{\"account\":{\"type\":\"chatgpt\",\"email\":\"a@b.c\",\"planType\":\"plus\"}}}"))
        XCTAssertEqual(plus, AccountIdentity(email: "a@b.c", plan: "Plus", type: .personal))
        let team = CodexAccount.parse(d("{\"result\":{\"account\":{\"planType\":\"team\"}}}"))
        XCTAssertEqual(team?.type, .business)
        XCTAssertNil(CodexAccount.parse(d("{\"error\":{\"message\":\"x\"}}")))
    }
}

final class StatuslineConfigTests: XCTestCase {
    let script = "/Users/me/Library/Application Support/Cooltime/cooltime-statusline.sh"
    func d(_ s: String) -> Data { s.data(using: .utf8)! }
    func obj(_ data: Data) -> [String: Any] { try! JSONSerialization.jsonObject(with: data) as! [String: Any] }

    func testAddsToEmptyOrMissingFile() throws {
        let c = try StatuslineConfig.plan(existing: nil, scriptPath: script)
        let sl = obj(c.newData)["statusLine"] as! [String: Any]
        XCTAssertEqual(sl["command"] as? String, "\"\(script)\"")
        XCTAssertFalse(c.alreadySet)
    }

    func testKeepsOtherSettingsAndWrapsExistingStatusline() throws {
        let existing = d("{\"theme\":\"dark\",\"statusLine\":{\"type\":\"command\",\"command\":\"echo it's me\",\"padding\":2}}")
        let c = try StatuslineConfig.plan(existing: existing, scriptPath: script)
        let root = obj(c.newData)
        XCTAssertEqual(root["theme"] as? String, "dark")
        let sl = root["statusLine"] as! [String: Any]
        XCTAssertEqual(sl["padding"] as? Int, 2)
        XCTAssertTrue((sl["command"] as! String).hasPrefix("\"\(script)\" '"))
        XCTAssertEqual(c.before, "echo it's me")
        XCTAssertTrue(StatuslineConfig.isSet(c.newData, scriptPath: script))
    }

    func testIdempotent() throws {
        let first = try StatuslineConfig.plan(existing: nil, scriptPath: script)
        let second = try StatuslineConfig.plan(existing: first.newData, scriptPath: script)
        XCTAssertTrue(second.alreadySet)
    }

    func testRevertRestoresOriginal() throws {
        let existing = d("{\"statusLine\":{\"type\":\"command\",\"command\":\"echo it's me\"}}")
        let c = try StatuslineConfig.plan(existing: existing, scriptPath: script)
        let back = try StatuslineConfig.revert(existing: c.newData, scriptPath: script)!
        XCTAssertEqual((obj(back)["statusLine"] as! [String: Any])["command"] as? String, "echo it's me")

        let fresh = try StatuslineConfig.plan(existing: d("{\"a\":1}"), scriptPath: script)
        let none = try StatuslineConfig.revert(existing: fresh.newData, scriptPath: script)!
        XCTAssertNil(obj(none)["statusLine"])
        XCTAssertEqual(obj(none)["a"] as? Int, 1)
    }

    func testRefusesToTouchUnreadableOrUnknownShapes() {
        XCTAssertThrowsError(try StatuslineConfig.plan(existing: d("not json"), scriptPath: script))
        XCTAssertThrowsError(try StatuslineConfig.plan(existing: d("{\"statusLine\":\"x\"}"), scriptPath: script))
        XCTAssertNil(try StatuslineConfig.revert(existing: d("{\"statusLine\":{\"type\":\"command\",\"command\":\"mine\"}}"), scriptPath: script))
    }
}

final class ClaudeUsageTextTests: XCTestCase {
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tokyo
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    func testParsesRealOutput() throws {
        let text = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 20% used · resets Nov 1 at 5:19pm (Asia/Tokyo)
        Current week (all models): 3% used · resets Nov 7 at 4:59pm (Asia/Tokyo)
        """
        let s = try ClaudeUsageText.parse(text, now: date("2026-11-01 13:00"))
        XCTAssertEqual(s.windows.map(\.label), ["5時間枠", "週の枠"])
        XCTAssertEqual(s.windows[0].usedPercent, 20)
        XCTAssertEqual(s.windows[0].resetsAt, date("2026-11-01 17:19"))
        XCTAssertEqual(s.windows[1].resetsAt, date("2026-11-07 16:59"))
    }

    func testExhaustedSessionIsLimited() throws {
        let now = date("2026-11-01 13:00")
        let s = try ClaudeUsageText.parse("Current session: 100% used · resets Nov 1 at 5pm (Asia/Tokyo)", now: now)
        XCTAssertEqual(evaluate(s, now: now), .limited(until: date("2026-11-01 17:00")))
    }

    func testYearRolloverAndNoonMidnight() {
        XCTAssertEqual(ClaudeUsageText.resetDate("Jan 2 at 12am", timeZone: "Asia/Tokyo", now: date("2026-12-30 10:00")),
                       date("2027-01-02 00:00"))
        XCTAssertEqual(ClaudeUsageText.resetDate("Nov 3 at 12pm", timeZone: "Asia/Tokyo", now: date("2026-11-01 10:00")),
                       date("2026-11-03 12:00"))
    }

    func testTimeOnlyMeansNextOccurrence() {
        XCTAssertEqual(ClaudeUsageText.resetDate("9:30am", timeZone: "Asia/Tokyo", now: date("2026-11-01 13:00")),
                       date("2026-11-02 09:30"))
        XCTAssertEqual(ClaudeUsageText.resetDate("5:19pm", timeZone: "Asia/Tokyo", now: date("2026-11-01 13:00")),
                       date("2026-11-01 17:19"))
    }

    func testUnknownOutputIsAnError() {
        XCTAssertThrowsError(try ClaudeUsageText.parse("Unknown command: /usage", now: Date()))
    }
}

final class StopHookConfigTests: XCTestCase {
    let script = "/Users/me/Library/Application Support/Cooltime/cooltime-statusline.sh"
    let hook = #"[ -n "$COOLTIME_USAGE_PROBE" ] || touch "$HOME/Library/Application Support/Cooltime/claude-ping""#
    func d(_ s: String) -> Data { s.data(using: .utf8)! }
    func obj(_ data: Data) -> [String: Any] { try! JSONSerialization.jsonObject(with: data) as! [String: Any] }

    func testAddsHookAlongsideExistingHooks() throws {
        let existing = d(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#)
        let c = try StatuslineConfig.plan(existing: existing, scriptPath: script, hookCommand: hook)
        XCTAssertTrue(c.addsHook)
        let stop = (obj(c.newData)["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 2)
        XCTAssertTrue(StatuslineConfig.isSet(c.newData, scriptPath: script, hookCommand: hook))
    }

    func testAddsOnlyHookWhenStatuslineAlreadySet() throws {
        let first = try StatuslineConfig.plan(existing: nil, scriptPath: script)
        XCTAssertFalse(StatuslineConfig.isSet(first.newData, scriptPath: script, hookCommand: hook))
        let second = try StatuslineConfig.plan(existing: first.newData, scriptPath: script, hookCommand: hook)
        XCTAssertTrue(second.addsHook)
        XCTAssertFalse(second.alreadySet)
        let third = try StatuslineConfig.plan(existing: second.newData, scriptPath: script, hookCommand: hook)
        XCTAssertTrue(third.alreadySet)
    }

    func testRevertRemovesOnlyOurs() throws {
        let existing = d(#"{"a":1,"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#)
        let c = try StatuslineConfig.plan(existing: existing, scriptPath: script, hookCommand: hook)
        let back = try StatuslineConfig.revert(existing: c.newData, scriptPath: script, hookCommand: hook)!
        let root = obj(back)
        XCTAssertNil(root["statusLine"])
        let stop = (root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 1)
        XCTAssertEqual(root["a"] as? Int, 1)

        let fresh = try StatuslineConfig.plan(existing: nil, scriptPath: script, hookCommand: hook)
        let empty = try StatuslineConfig.revert(existing: fresh.newData, scriptPath: script, hookCommand: hook)!
        XCTAssertTrue(obj(empty).isEmpty)
    }
}

final class OutdatedDataTests: XCTestCase {
    let clock = FixedClock(Date(timeIntervalSince1970: 1_800_000_000))

    /// 取得した後に戻り時刻を過ぎた枠は、「使用可能」とは言わず、再確認を促す。
    func testAvailableWindowPastResetBecomesStale() {
        let reset = clock.now.addingTimeInterval(600)
        let s = Snapshot(windows: [UsageWindow(label: "5時間枠", usedPercent: 12, resetsAt: reset)], fetchedAt: clock.now)
        XCTAssertEqual(evaluate(s, now: clock.now), .available)
        clock.advance(by: 601)
        XCTAssertEqual(evaluate(s, now: clock.now), .stale(since: reset))
    }

    /// 戻り時刻を過ぎたあとに取得したデータなら、そのまま信用する。
    func testFreshDataAfterResetIsAvailable() {
        let reset = clock.now.addingTimeInterval(-600)
        let s = Snapshot(windows: [UsageWindow(label: "5時間枠", usedPercent: 12, resetsAt: reset)], fetchedAt: clock.now)
        XCTAssertEqual(evaluate(s, now: clock.now), .available)
    }
}

final class AppVersionTests: XCTestCase {
    func testIsNewer() {
        XCTAssertTrue(AppVersion.isNewer("v0.4.0", than: "0.3.0"))
        XCTAssertTrue(AppVersion.isNewer("0.10.0", than: "0.9.5"))
        XCTAssertTrue(AppVersion.isNewer("v1.0", than: "0.9.9"))
        XCTAssertFalse(AppVersion.isNewer("v0.3.0", than: "0.3.0"))
        XCTAssertFalse(AppVersion.isNewer("v0.2.9", than: "0.3.0"))
        XCTAssertFalse(AppVersion.isNewer("nightly", than: "0.3.0"))
        XCTAssertTrue(AppVersion.isNewer("v0.0.1", than: "0.0.0"))
    }
}
