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
        XCTAssertThrowsError(try ClaudeStatusline.parse(d(#"{"model":{}}"#), fetchedAt: at))
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
        XCTAssertEqual(try VercelAIGateway.parse(d(#"{"balance":"95.50","total_used":"4"}"#), fetchedAt: at).credit?.amount, 95.5)
        let ds = try DeepSeek.parse(d(#"{"balance_infos":[{"currency":"USD","total_balance":"12.00"}]}"#), fetchedAt: at)
        XCTAssertEqual(formatMoney(ds.credit!), "$12.00")
    }

    func testOpenRouterRequiresLimit() throws {
        XCTAssertThrowsError(try OpenRouter.parse(d(#"{"data":{"limit":null,"limit_remaining":null}}"#), fetchedAt: at))
        let s = try OpenRouter.parse(d(#"{"data":{"limit":20,"limit_remaining":18.4,"limit_reset":"monthly"}}"#), fetchedAt: at)
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
        XCTAssertNil(ClaudeAccount.parse(d(#"{"projects":{}}"#)))
    }

    func testCodexAccountMapsPlanToType() {
        let plus = CodexAccount.parse(d(#"{"id":3,"result":{"account":{"type":"chatgpt","email":"a@b.c","planType":"plus"}}}"#))
        XCTAssertEqual(plus, AccountIdentity(email: "a@b.c", plan: "Plus", type: .personal))
        let team = CodexAccount.parse(d(#"{"result":{"account":{"planType":"team"}}}"#))
        XCTAssertEqual(team?.type, .business)
        XCTAssertNil(CodexAccount.parse(d(#"{"error":{"message":"x"}}"#)))
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
        let existing = d(#"{"theme":"dark","statusLine":{"type":"command","command":"echo it's me","padding":2}}"#)
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
        let existing = d(#"{"statusLine":{"type":"command","command":"echo it's me"}}"#)
        let c = try StatuslineConfig.plan(existing: existing, scriptPath: script)
        let back = try StatuslineConfig.revert(existing: c.newData, scriptPath: script)!
        XCTAssertEqual((obj(back)["statusLine"] as! [String: Any])["command"] as? String, "echo it's me")

        let fresh = try StatuslineConfig.plan(existing: d(#"{"a":1}"#), scriptPath: script)
        let none = try StatuslineConfig.revert(existing: fresh.newData, scriptPath: script)!
        XCTAssertNil(obj(none)["statusLine"])
        XCTAssertEqual(obj(none)["a"] as? Int, 1)
    }

    func testRefusesToTouchUnreadableOrUnknownShapes() {
        XCTAssertThrowsError(try StatuslineConfig.plan(existing: d("not json"), scriptPath: script))
        XCTAssertThrowsError(try StatuslineConfig.plan(existing: d(#"{"statusLine":"x"}"#), scriptPath: script))
        XCTAssertNil(try StatuslineConfig.revert(existing: d(#"{"statusLine":{"type":"command","command":"mine"}}"#), scriptPath: script))
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

final class CodexErrorTextTests: XCTestCase {
    func d(_ s: String) -> Data { s.data(using: .utf8)! }

    func testNetworkErrorIsShortJapanese() {
        let data = d(#"{"id":2,"error":{"code":-32603,"message":"failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)"}}"#)
        XCTAssertThrowsError(try CodexRateLimits.parse(data, fetchedAt: Date())) { e in
            XCTAssertEqual((e as? ParseError)?.errorDescription, "Codex が ChatGPT に接続できませんでした（通信を確認）")
        }
    }

    func testAuthErrorSuggestsRelogin() {
        let data = d(#"{"id":2,"error":{"message":"401 Unauthorized"}}"#)
        XCTAssertThrowsError(try CodexRateLimits.parse(data, fetchedAt: Date())) { e in
            XCTAssertTrue((e as? ParseError)?.errorDescription?.contains("再ログイン") == true)
        }
    }
}

final class UsageHistoryTests: XCTestCase {
    let a = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func snap(_ used: Double, reset: Date, at: Date, label: String = "5時間枠") -> Snapshot {
        Snapshot(windows: [UsageWindow(label: label, usedPercent: used, resetsAt: reset)], fetchedAt: at)
    }

    func testPeakAndPeriodRollover() {
        var h = UsageHistory(startedAt: t0)
        let r1 = t0.addingTimeInterval(3600)
        h.observe(account: a, serviceID: "claude", snapshot: snap(20, reset: r1, at: t0), now: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(55, reset: r1.addingTimeInterval(60), at: t0.addingTimeInterval(600)),
                  now: t0.addingTimeInterval(600))
        XCTAssertEqual(h.open.count, 1)
        XCTAssertEqual(h.open.values.first?.peakUsed, 55)
        // 次の期間
        let r2 = r1.addingTimeInterval(5 * 3600)
        h.observe(account: a, serviceID: "claude", snapshot: snap(5, reset: r2, at: r1.addingTimeInterval(60)), now: r1.addingTimeInterval(60))
        XCTAssertEqual(h.periods.count, 1)
        XCTAssertEqual(h.periods[0].peakUsed, 55)
    }

    func testLimitIsCountedOncePerPeriodAndWaitTimeSums() {
        var h = UsageHistory(startedAt: t0)
        let reset = t0.addingTimeInterval(2 * 3600)
        h.observe(account: a, serviceID: "claude", snapshot: snap(100, reset: reset, at: t0), now: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(100, reset: reset, at: t0.addingTimeInterval(60)), now: t0.addingTimeInterval(60))
        XCTAssertEqual(h.limits.count, 1)
        let s = h.summary(from: t0, to: t0.addingTimeInterval(86400), now: t0.addingTimeInterval(86400))
        XCTAssertEqual(s.limitHits, 1)
        XCTAssertEqual(s.waited, 2 * 3600, accuracy: 1)
    }

    /// リセットの直前まで見えていない期間は、使い残しを出さない（数字を作らない）。
    func testUnusedNeedsObservationNearReset() {
        let p = WindowPeriod(account: a, serviceID: "claude", label: "週の枠", resetsAt: t0.addingTimeInterval(7 * 86400),
                             peakUsed: 30, firstSeen: t0, lastSeen: t0.addingTimeInterval(86400), hitLimit: false)
        XCTAssertNil(p.unused)
        var q = p
        q.lastSeen = q.resetsAt.addingTimeInterval(-3600)
        XCTAssertEqual(q.unused, 70)
    }

    func testPlanDownSuggestionAfterThreeLightWeeks() {
        var h = UsageHistory(startedAt: t0)
        for i in 0..<3 {
            let reset = t0.addingTimeInterval(Double(i + 1) * 7 * 86400)
            h.periods.append(WindowPeriod(account: a, serviceID: "claude", label: "週の枠", resetsAt: reset, peakUsed: 30,
                                          firstSeen: reset.addingTimeInterval(-7 * 86400), lastSeen: reset.addingTimeInterval(-600),
                                          hitLimit: false))
        }
        let s = h.suggestions(now: t0.addingTimeInterval(22 * 86400), name: { _ in "Claude" })
        XCTAssertEqual(s.map(\.kind), [.planDown])
        XCTAssertTrue(s[0].text.contains("平均30%"))
    }

    func testNoSuggestionsWithoutEnoughData() {
        var h = UsageHistory(startedAt: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(10, reset: t0.addingTimeInterval(3600), at: t0), now: t0)
        XCTAssertTrue(h.suggestions(now: t0, name: { _ in "Claude" }).isEmpty)
    }

    func testUseItOrLoseIt() {
        var h = UsageHistory(startedAt: t0)
        let reset = t0.addingTimeInterval(10 * 3600)
        h.observe(account: a, serviceID: "claude", snapshot: snap(35, reset: reset, at: t0, label: "週の枠"), now: t0)
        let s = h.suggestions(now: t0, name: { _ in "Claude" })
        XCTAssertEqual(s.map(\.kind), [.useItOrLoseIt])
        XCTAssertTrue(s[0].text.contains("あと65%"))
    }

    func testRangeIsMondayBasedWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let f = ISO8601DateFormatter()
        let wed = f.date(from: "2026-11-04T03:00:00Z")!  // 水曜 12:00 JST
        let (s, e) = UsageHistory.range(.week, containing: wed, calendar: cal)
        XCTAssertEqual(f.string(from: s), "2026-11-01T15:00:00Z")  // 月曜 0:00 JST
        XCTAssertEqual(e.timeIntervalSince(s), 7 * 86400)
    }
}

final class DurationTests: XCTestCase {
    func testFormatDuration() {
        XCTAssertEqual(formatDuration(0), "0分")
        XCTAssertEqual(formatDuration(45 * 60), "45分")
        XCTAssertEqual(formatDuration(6 * 3600 + 12 * 60), "6時間12分")
        XCTAssertEqual(formatDuration(30 * 3600), "30時間")
    }
}

final class CharacterMotionTests: XCTestCase {
    static let json = """
    {"states":{
      "limit":{"targets":{"root":{"duration_s":3,"easing":"ease-in-out","keyframes":{"0":{"translateY":0},"50":{"translateY":-9},"100":{"translateY":0}}}}},
      "ok":{"targets":{"eyes":{"duration_s":3.4,"easing":"linear","keyframes":{"0":{"scaleY":1},"90":{"scaleY":1},"94":{"scaleY":0.08},"100":{"scaleY":1}}}}},
      "fail":{"targets":{"root":{"duration_s":4,"easing":"ease-in-out","keyframes":{"0":{"rotate":0},"88":{"rotate":0},"91":{"rotate":-5},"100":{"rotate":0}}}}}
    }}
    """
    let motion = CharacterMotion(json: Data(CharacterMotionTests.json.utf8))!

    func testEaseInOutPeaksAtMiddle() {
        XCTAssertEqual(motion.transform(state: .limit, group: "root", at: 0).ty, 0, accuracy: 1e-9)
        XCTAssertEqual(motion.transform(state: .limit, group: "root", at: 1.5).ty, -9, accuracy: 1e-9)
        XCTAssertEqual(motion.transform(state: .limit, group: "root", at: 0.75).ty, -4.5, accuracy: 1e-9)  // 真ん中は、どちらの式でも半分
        XCTAssertEqual(motion.transform(state: .limit, group: "root", at: 3).ty, 0, accuracy: 1e-9)       // 1周して戻る
    }

    func testLinearBlink() {
        XCTAssertEqual(motion.transform(state: .ok, group: "eyes", at: 1).scaleY, 1, accuracy: 1e-9)
        XCTAssertEqual(motion.transform(state: .ok, group: "eyes", at: 3.4 * 0.92).scaleY, 0.54, accuracy: 1e-6)
    }

    func testUnknownGroupIsIdentityAndPeriods() {
        XCTAssertEqual(motion.transform(state: .ok, group: "root", at: 1), GroupTransform())
        XCTAssertEqual(motion.period(state: .limit), 3)
        XCTAssertEqual(motion.groups(state: .fail), ["root"])
    }

    func testNegativeTimeWraps() {
        XCTAssertEqual(motion.transform(state: .limit, group: "root", at: -1.5).ty, -9, accuracy: 1e-9)
    }

    func testBundledMotionFileParses() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("characters/motion.json")
        let m = try XCTUnwrap(CharacterMotion(json: try Data(contentsOf: url)))
        XCTAssertEqual(m.groups(state: .ok), ["eyes", "look", "root"])
        XCTAssertEqual(m.groups(state: .limit), ["root", "zz"])
        XCTAssertEqual(m.groups(state: .fail), ["root"])
    }
}

final class MenuBarDisplayTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func avail(_ used: Double, _ source: String = "a") -> MenuBarCandidate {
        MenuBarCandidate(state: .available,
                         snapshot: Snapshot(windows: [UsageWindow(label: "5時間枠", usedPercent: used, resetsAt: now.addingTimeInterval(3600))], fetchedAt: now),
                         fetchFailed: false, source: source)
    }
    func limited(_ minutes: Double, _ source: String = "a") -> MenuBarCandidate {
        MenuBarCandidate(state: .limited(until: now.addingTimeInterval(minutes * 60)), snapshot: nil, fetchFailed: false, source: source)
    }

    func testLimitedShowsEarliestOnly() {
        let d = makeMenuBarDisplay([limited(300, "x"), limited(43, "claude"), avail(10)])
        XCTAssertEqual(d, .limited(until: now.addingTimeInterval(43 * 60), source: "claude"))
        XCTAssertEqual(d.text(now: now), "あと43分")
        XCTAssertEqual(d.characterState, .limit)
        XCTAssertEqual(d.source, "claude")
    }

    func testNoLimitShowsLowestRemainingWithItsSource() {
        let d = makeMenuBarDisplay([avail(13, "a"), avail(38, "codex"), avail(5, "c")])
        XCTAssertEqual(d, .remaining(percent: 62, source: "codex", scope: nil))
        XCTAssertEqual(d.text(now: now), "残り62%")
        XCTAssertEqual(d.characterState, .ok)
    }

    func testFailedItemsNumbersAreNotUsed() {
        var old = avail(90); old.fetchFailed = true
        let stale = MenuBarCandidate(state: .stale(since: now), snapshot: avail(95).snapshot, fetchFailed: false)
        XCTAssertEqual(makeMenuBarDisplay([old, stale, avail(40, "ok")]), .remaining(percent: 60, source: "ok", scope: nil))
    }

    func testAllFailedShowsCharacterOnly() {
        var old = avail(90); old.fetchFailed = true
        let d = makeMenuBarDisplay([old, MenuBarCandidate(state: .unset, snapshot: nil, fetchFailed: false)])
        XCTAssertEqual(d, .failed)
        XCTAssertNil(d.text(now: now))
        XCTAssertNil(d.source)
        XCTAssertEqual(d.characterState, .fail)
        XCTAssertEqual(makeMenuBarDisplay([]), .failed)
    }

    func testCreditUsedOnlyWhenNoPercent() {
        let credit = { (amount: Double, source: String) in
            MenuBarCandidate(state: .available, snapshot: Snapshot(credit: CreditBalance(amount: amount, currency: "USD"), fetchedAt: self.now),
                             fetchFailed: false, source: source)
        }
        XCTAssertEqual(makeMenuBarDisplay([credit(95.5, "v"), credit(18.4, "openrouter")]), .credit(text: "$18.40", source: "openrouter"))
        XCTAssertEqual(makeMenuBarDisplay([credit(18.4, "o"), avail(70, "claude")]), .remaining(percent: 30, source: "claude", scope: nil))
    }

    func twoWindows(fiveHourUsed: Double, weeklyUsed: Double, source: String = "claude") -> MenuBarCandidate {
        MenuBarCandidate(state: .available,
                         snapshot: Snapshot(windows: [
                            UsageWindow(label: "5時間枠", usedPercent: fiveHourUsed, resetsAt: now.addingTimeInterval(3600)),
                            UsageWindow(label: "週の枠", usedPercent: weeklyUsed, resetsAt: now.addingTimeInterval(5 * 86400))], fetchedAt: now),
                         fetchFailed: false, source: source)
    }

    /// 5時間枠を出す。週の枠のほうが少なくても、10%を切るまでは、5時間枠。
    func testFiveHourWindowWinsOverWeekly() {
        let d = makeMenuBarDisplay([twoWindows(fiveHourUsed: 13, weeklyUsed: 60)])
        XCTAssertEqual(d, .remaining(percent: 87, source: "claude", scope: nil))
        XCTAssertEqual(d.text(now: now), "残り87%")
    }

    func testWeeklyShownOnlyUnderTenPercent() {
        let d = makeMenuBarDisplay([twoWindows(fiveHourUsed: 13, weeklyUsed: 91)])  // 週の残り 9%
        XCTAssertEqual(d, .remaining(percent: 9, source: "claude", scope: "週"))
        XCTAssertEqual(d.text(now: now), "週残り9%")
        // ちょうど10%は、まだ5時間枠
        XCTAssertEqual(makeMenuBarDisplay([twoWindows(fiveHourUsed: 13, weeklyUsed: 90)]), .remaining(percent: 87, source: "claude", scope: nil))
    }

    func testWeeklyAlertComesFromAnyService() {
        let d = makeMenuBarDisplay([twoWindows(fiveHourUsed: 10, weeklyUsed: 20, source: "claude"),
                                    twoWindows(fiveHourUsed: 50, weeklyUsed: 96, source: "codex")])
        XCTAssertEqual(d, .remaining(percent: 4, source: "codex", scope: "週"))
    }

    func testMonthlyOnlyServiceFallsBackToPlainRemaining() {
        let monthly = MenuBarCandidate(state: .available,
                                       snapshot: Snapshot(windows: [UsageWindow(label: "月の文字数", usedPercent: 59, resetsAt: now.addingTimeInterval(86400))], fetchedAt: now),
                                       fetchFailed: false, source: "elevenlabs")
        XCTAssertEqual(makeMenuBarDisplay([monthly]), .remaining(percent: 41, source: "elevenlabs", scope: nil))
        // 5時間枠があるときは、そちらが先
        XCTAssertEqual(makeMenuBarDisplay([monthly, avail(20, "claude")]), .remaining(percent: 80, source: "claude", scope: nil))
    }

    func testDaysOnlyWhenOverOneDay() {
        XCTAssertEqual(formatRemainingShort(until: now.addingTimeInterval((2 * 24 + 5) * 3600), now: now), "あと2日")
        XCTAssertEqual(formatRemainingShort(until: now.addingTimeInterval(23 * 3600 + 59 * 60), now: now), "あと23時間59分")
        XCTAssertEqual(formatRemainingShort(until: now.addingTimeInterval(24 * 3600), now: now), "あと1日")
    }
}

final class UsageBucketTests: XCTestCase {
    let a = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00:00 UTC

    func snap(_ used: Double, at: Date, label: String = "週の枠") -> Snapshot {
        Snapshot(windows: [UsageWindow(label: label, usedPercent: used, resetsAt: t0.addingTimeInterval(5 * 86400))], fetchedAt: at)
    }

    func testIncreaseIsRecordedInTheHourItWasSeen() {
        var h = UsageHistory(startedAt: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(10, at: t0), now: t0)                       // 最初の値は、数えない
        h.observe(account: a, serviceID: "claude", snapshot: snap(13, at: t0.addingTimeInterval(600)), now: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(13, at: t0.addingTimeInterval(1200)), now: t0) // 増えていない
        h.observe(account: a, serviceID: "claude", snapshot: snap(15, at: t0.addingTimeInterval(7200)), now: t0) // 2時間後
        XCTAssertEqual(h.buckets.count, 2)
        XCTAssertEqual(h.buckets.map(\.points).reduce(0, +), 5)
        XCTAssertEqual(h.buckets[0].points, 3)
    }

    func testShortWindowsAreNotCounted() {
        var h = UsageHistory(startedAt: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(10, at: t0, label: "5時間枠"), now: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(40, at: t0.addingTimeInterval(60), label: "5時間枠"), now: t0)
        XCTAssertTrue(h.buckets.isEmpty)
        XCTAssertTrue(UsageHistory.isBudgetWindow("週の枠"))
        XCTAssertTrue(UsageHistory.isBudgetWindow("月の文字数"))
        XCTAssertFalse(UsageHistory.isBudgetWindow("5時間枠"))
    }

    func testOldRecordWithoutBucketsStillDecodes() throws {
        let json = #"{"startedAt":1800000000,"periods":[],"limits":[],"open":{}}"#
        let h = try JSONDecoder.cooltimeTest.decode(UsageHistory.self, from: Data(json.utf8))
        XCTAssertEqual(h.startedAt, t0)
        XCTAssertTrue(h.buckets.isEmpty)
    }

    func testBarsByHourAndByDayAndHourOfDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var h = UsageHistory(startedAt: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(10, at: t0), now: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(12, at: t0.addingTimeInterval(60)), now: t0)          // 08時 +2
        h.observe(account: a, serviceID: "claude", snapshot: snap(15, at: t0.addingTimeInterval(3 * 3600)), now: t0)    // 11時 +3
        let day = cal.startOfDay(for: t0)
        let hourly = h.usageBars(span: .day, from: day, to: day.addingTimeInterval(86400), calendar: cal)
        XCTAssertEqual(hourly.map(\.points), [2, 3])
        let daily = h.usageBars(span: .week, from: day, to: day.addingTimeInterval(7 * 86400), calendar: cal)
        XCTAssertEqual(daily.count, 1)
        XCTAssertEqual(daily[0].points, 5)
        let byHour = h.hourOfDayTotals(from: day, to: day.addingTimeInterval(86400), calendar: cal)
        XCTAssertEqual(byHour[8], 2)
        XCTAssertEqual(byHour[11], 3)
        XCTAssertEqual(byHour.reduce(0, +), 5)
    }

    func testLimitMarksInRange() {
        var h = UsageHistory(startedAt: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(100, at: t0, label: "5時間枠"), now: t0)
        XCTAssertEqual(h.limitMarks(from: t0.addingTimeInterval(-60), to: t0.addingTimeInterval(60)).count, 1)
        XCTAssertTrue(h.limitMarks(from: t0.addingTimeInterval(3600), to: t0.addingTimeInterval(7200)).isEmpty)
    }

    func testForgetRemovesBuckets() {
        var h = UsageHistory(startedAt: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(10, at: t0), now: t0)
        h.observe(account: a, serviceID: "claude", snapshot: snap(20, at: t0.addingTimeInterval(60)), now: t0)
        XCTAssertFalse(h.buckets.isEmpty)
        h.forget(account: a)
        XCTAssertTrue(h.buckets.isEmpty)
    }
}

private extension JSONDecoder {
    static var cooltimeTest: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }
}

final class PlanCatalogTests: XCTestCase {
    func testMatchByIdOrName() {
        XCTAssertEqual(PlanCatalog.match(serviceID: "codex", planName: "Plus")?.id, "plus")
        XCTAssertEqual(PlanCatalog.match(serviceID: "codex", planName: "pro")?.usdMonthly, 200)
        XCTAssertEqual(PlanCatalog.match(serviceID: "claude", planName: "Max 5x")?.id, "max5x")
        XCTAssertEqual(PlanCatalog.match(serviceID: "claude", planName: "max20x")?.usdMonthly, 200)
    }

    func testUnknownPlanIsNotInvented() {
        XCTAssertNil(PlanCatalog.match(serviceID: "codex", planName: "Team"))
        XCTAssertNil(PlanCatalog.match(serviceID: "codex", planName: nil))
        XCTAssertNil(PlanCatalog.match(serviceID: "firecrawl", planName: "Hobby"))
        XCTAssertTrue(PlanCatalog.options(for: "elevenlabs").isEmpty)
    }

    func testPriceText() {
        XCTAssertEqual(PlanCatalog.option(serviceID: "claude", id: "max5x")?.priceText, "月 $100")
        XCTAssertNil(PlanCatalog.option(serviceID: "claude", id: nil))
    }

    func testOldAccountWithoutPlanStillDecodes() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","serviceID":"claude","name":"","type":"personal","paymentURL":"","slot":"default"}"#
        let d = JSONDecoder()
        let a = try d.decode(Account.self, from: Data(json.utf8))
        XCTAssertNil(a.planID)
        XCTAssertNil(a.monthlyPrice)
    }
}

final class ClaudePlanTests: XCTestCase {
    func d(_ s: String) -> Data { s.data(using: .utf8)! }

    /// 実機の値（organizationType が claude_pro、ほかは空か、ただの名前）から、Pro と分かる。
    func testProFromOrganizationType() {
        let id = ClaudeAccount.parse(d(#"{"oauthAccount":{"emailAddress":"a@b.c","organizationType":"claude_pro","organizationRateLimitTier":"default_claude_ai","userRateLimitTier":null,"seatTier":null}}"#))
        XCTAssertEqual(id?.plan, "Pro")
        XCTAssertEqual(PlanCatalog.match(serviceID: "claude", planName: id?.plan)?.id, "pro")
    }

    func testMaxNeedsTierToTellSizes() {
        let five = ClaudeAccount.parse(d(#"{"oauthAccount":{"emailAddress":"a@b.c","organizationType":"claude_max","userRateLimitTier":"default_claude_max_5x"}}"#))
        XCTAssertEqual(five?.plan, "Max 5x")
        let twenty = ClaudeAccount.parse(d(#"{"oauthAccount":{"emailAddress":"a@b.c","organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_20x"}}"#))
        XCTAssertEqual(PlanCatalog.match(serviceID: "claude", planName: twenty?.plan)?.usdMonthly, 200)
        // どちらか分からないときは、作らない
        let unknown = ClaudeAccount.parse(d(#"{"oauthAccount":{"emailAddress":"a@b.c","organizationType":"claude_max"}}"#))
        XCTAssertNil(unknown?.plan)
    }

    func testTeamAndMissingAreNotInvented() {
        XCTAssertNil(ClaudeAccount.parse(d(#"{"oauthAccount":{"emailAddress":"a@b.c","organizationType":"claude_team"}}"#))?.plan)
        XCTAssertNil(ClaudeAccount.parse(d(#"{"oauthAccount":{"emailAddress":"a@b.c"}}"#))?.plan)
    }
}

final class CompactTextTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCompactShortensRemaining() {
        XCTAssertEqual(MenuBarDisplay.remaining(percent: 65, source: "claude", scope: nil).text(now: now, compact: true), "65%")
        XCTAssertEqual(MenuBarDisplay.remaining(percent: 65, source: "claude", scope: nil).text(now: now), "残り65%")
        XCTAssertEqual(MenuBarDisplay.remaining(percent: 9, source: "claude", scope: "週").text(now: now, compact: true), "週9%")
        XCTAssertEqual(MenuBarDisplay.remaining(percent: 9, source: "claude", scope: "週").text(now: now), "週残り9%")
        XCTAssertEqual(MenuBarDisplay.limited(until: now.addingTimeInterval(43 * 60), source: "x").text(now: now, compact: true), "あと43分")
        XCTAssertNil(MenuBarDisplay.failed.text(now: now, compact: true))
    }
}

final class MoreAPIParserTests: XCTestCase {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    func d(_ s: String) -> Data { s.data(using: .utf8)! }

    func testStabilityLumaRunwayPhotoroomMeshyBalances() throws {
        XCTAssertEqual(try StabilityAI.parse(d(#"{"credits": 8.4}"#), fetchedAt: at).credit?.amount, 8.4)
        let luma = try LumaAI.parse(d(#"{"credit_balance": 1234}"#), fetchedAt: at).credit
        XCTAssertEqual(luma?.amount, 12.34)  // セント → ドル
        XCTAssertEqual(luma?.currency, "USD")
        XCTAssertEqual(try RunwayAPI.parse(d(#"{"creditBalance": 1000, "tier": {}}"#), fetchedAt: at).credit?.amount, 1000)
        XCTAssertEqual(try Photoroom.parse(d(#"{"credits": {"available": 9, "subscription": 10}}"#), fetchedAt: at).credit?.amount, 9)
        let meshy = try Meshy.parse(d(#"{"balance": 250, "monthly_resets_at": "2026-12-01T00:00:00Z"}"#), fetchedAt: at).credit
        XCTAssertEqual(meshy?.amount, 250)
        XCTAssertNotNil(meshy?.resetsAt)
        XCTAssertNil(try Meshy.parse(d(#"{"balance": 250}"#), fetchedAt: at).credit?.resetsAt)  // 無ければ作らない
    }

    func testMissingFieldsAreErrorsNotGuesses() {
        XCTAssertThrowsError(try StabilityAI.parse(d("{}"), fetchedAt: at))
        XCTAssertThrowsError(try LumaAI.parse(d(#"{"balance": 1}"#), fetchedAt: at))
        XCTAssertThrowsError(try RunwayAPI.parse(d("{}"), fetchedAt: at))
        XCTAssertThrowsError(try Photoroom.parse(d(#"{"credits": {}}"#), fetchedAt: at))
        XCTAssertThrowsError(try Meshy.parse(d("{}"), fetchedAt: at))
        XCTAssertThrowsError(try Apify.parse(d(#"{"data": {}}"#), fetchedAt: at))
        XCTAssertThrowsError(try SerpAPI.parse(d("{}"), fetchedAt: at))
        XCTAssertThrowsError(try DeepL.parse(d("{}"), fetchedAt: at))
    }

    func testApifyMonthlyUsageAndCycleEnd() throws {
        let s = try Apify.parse(d(#"""
        {"data": {"monthlyUsageCycle": {"startAt": "2026-11-01T00:00:00.000Z", "endAt": "2026-11-30T23:59:59.999Z"},
                  "limits": {"maxMonthlyUsageUsd": 50}, "current": {"monthlyUsageUsd": 12.5}}}
        """#), fetchedAt: at)
        XCTAssertEqual(s.windows[0].usedPercent ?? 0, 25, accuracy: 0.001)
        XCTAssertNotNil(s.windows[0].resetsAt)
    }

    func testSerpAPIRemainingAndRenewalDate() throws {
        let s = try SerpAPI.parse(d(#"{"searches_per_month": 100, "this_month_usage": 30, "plan_searches_left": 70, "plan_renewal_date": "2026-12-01"}"#), fetchedAt: at)
        XCTAssertEqual(s.windows[0].usedPercent ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(s.windows[0].remainingCount, 70)
        XCTAssertEqual(availableSummary(s), "残り70")
        XCTAssertNotNil(s.windows[0].resetsAt)
        // 残りが無ければ、使用量から計算する
        let t = try SerpAPI.parse(d(#"{"searches_per_month": 100, "this_month_usage": 100}"#), fetchedAt: at)
        XCTAssertTrue(t.windows[0].isExhausted)
        XCTAssertNil(t.windows[0].resetsAt)
    }

    func testDeepLUsageAndEndpoint() throws {
        let s = try DeepL.parse(d(#"{"character_count": 250000, "character_limit": 500000}"#), fetchedAt: at)
        XCTAssertEqual(s.windows[0].remainingPercent ?? 0, 50, accuracy: 0.001)
        XCTAssertNil(s.windows[0].resetsAt)
        XCTAssertThrowsError(try DeepL.parse(d(#"{"character_count": 1, "character_limit": 0}"#), fetchedAt: at))
        XCTAssertEqual(DeepL.endpoint(forKey: "abc:fx"), "https://api-free.deepl.com/v2/usage")
        XCTAssertEqual(DeepL.endpoint(forKey: "abc"), "https://api.deepl.com/v2/usage")
    }

    func testDateOnlyIsParsed() {
        XCTAssertNotNil(parseDate("2026-12-01"))
        XCTAssertEqual(formatMoney(CreditBalance(amount: 8.4, currency: "credits")), "8.4")
        XCTAssertEqual(formatMoney(CreditBalance(amount: 250, currency: "credits")), "250")
    }

    func testNewServicesAreInTheCatalogInSheetOrder() {
        let ids = Catalog.automatic.map(\.id)
        XCTAssertEqual(Array(ids.suffix(11)), ["runway", "luma", "stability", "apify", "serpapi", "deepl", "photoroom", "meshy",
                                               "copilot", "synthesia", "tripo"])
        XCTAssertEqual(Set(ids).count, ids.count)  // IDは重ならない
        XCTAssertTrue(Catalog.automatic.suffix(11).allSatisfy { $0.method == .apiKey && $0.apiKeyHelp != nil })
    }
}

final class DocumentedAPITests: XCTestCase {
    func d(_ s: String) -> Data { s.data(using: .utf8)! }
    // 2026-11-05 12:00 UTC
    let at = Date(timeIntervalSince1970: 1_793_880_000)

    func testCopilotSumsOnlyAICreditsAndResetsNextMonthUTC() throws {
        let json = #"{"timePeriod":{"year":2026,"month":11},"user":"monalisa","usageItems":[{"unitType":"ai-credits","grossQuantity":300},{"unitType":"ai-credits","grossQuantity":150},{"unitType":"requests","grossQuantity":999}]}"#
        let w = try CopilotCredits.parse(d(json), allowance: 1_500, fetchedAt: at).windows.first
        XCTAssertEqual(w?.usedPercent ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(w?.remainingCount, 1_050)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour], from: w!.resetsAt!)
        XCTAssertEqual([c.year!, c.month!, c.day!, c.hour!], [2026, 12, 1, 0])
    }

    func testCopilotNeedsPlanAndCapsAtZeroRemaining() throws {
        XCTAssertThrowsError(try CopilotCredits.parse(d(#"{"usageItems":[]}"#), allowance: nil, fetchedAt: at))
        let over = try CopilotCredits.parse(d(#"{"usageItems":[{"unitType":"ai-credits","grossQuantity":2000}]}"#), allowance: 1_500, fetchedAt: at).windows.first
        XCTAssertEqual(over?.usedPercent, 100)
        XCTAssertEqual(over?.remainingCount, 0)
        XCTAssertThrowsError(try CopilotCredits.parse(d("{}"), allowance: 1_500, fetchedAt: at))
    }

    func testCopilotRequestPathAndPlans() throws {
        XCTAssertEqual(CopilotCredits.path(login: "mona", now: at),
                       "https://api.github.com/users/mona/settings/billing/ai_credit/usage?year=2026&month=11")
        XCTAssertEqual(try GitHubUser.login(d(#"{"login":"mona"}"#)), "mona")
        XCTAssertEqual(PlanCatalog.options(for: "copilot").map(\.monthlyCredits), [1_500, 7_000, 20_000])
    }

    func testSynthesiaDecimalStrings() throws {
        let json = #"{"period":{"startsAt":"2026-11-01T00:00:00Z","endsAt":"2026-12-01T00:00:00Z"},"credits":{"total":"1000.00","consumed":"250.50","available":"749.50","unit":"credits"}}"#
        let w = try Synthesia.parse(d(json), fetchedAt: at).windows.first
        XCTAssertEqual(w?.usedPercent ?? 0, 25.05, accuracy: 0.001)
        XCTAssertEqual(w?.remainingCount, 749.5)
        XCTAssertNotNil(w?.resetsAt)
        XCTAssertThrowsError(try Synthesia.parse(d(#"{"credits":{}}"#), fetchedAt: at))
    }

    func testTripoBalanceAndFrozen() throws {
        let c = try Tripo.parse(d(#"{"balance": 10000.00, "frozen": 200.00}"#), fetchedAt: at).credit
        XCTAssertEqual(c?.amount, 10000)
        XCTAssertEqual(c?.note, "処理中で確保されている分 200")
        XCTAssertNil(try Tripo.parse(d(#"{"data":{"balance": 5, "frozen": 0}}"#), fetchedAt: at).credit?.note)
        XCTAssertThrowsError(try Tripo.parse(d("{}"), fetchedAt: at))
    }
}

final class ManualImportTests: XCTestCase {
    let observed = Date(timeIntervalSince1970: 1_793_880_000)
    var later: Date { observed.addingTimeInterval(60) }

    func testCatalogIncludesManualEntriesWithoutClaimingLiveAPI() {
        XCTAssertEqual(ManualCatalog.all.count, 155)
        XCTAssertEqual(Catalog.all.count, 185)
        XCTAssertEqual(Set(Catalog.all.map(\.id)).count, Catalog.all.count)
        XCTAssertEqual(Catalog.service("sheet-11")?.name, "Google Antigravity")
        XCTAssertEqual(Catalog.service("sheet-20")?.method, .apiKey)
        XCTAssertEqual(Catalog.service("sheet-20")?.kind, .subscription)
        XCTAssertFalse(ManualCatalog.all.contains { $0.id == "sheet-20" })
        XCTAssertEqual(Catalog.service("sheet-86")?.method, .apiKey)
        XCTAssertEqual(Catalog.service("sheet-86")?.kind, .subscription)
        XCTAssertFalse(ManualCatalog.all.contains { $0.id == "sheet-86" })
        XCTAssertEqual(Catalog.service("sheet-87")?.method, .apiKey)
        XCTAssertEqual(Catalog.service("sheet-87")?.kind, .subscription)
        XCTAssertFalse(ManualCatalog.all.contains { $0.id == "sheet-87" })
        XCTAssertEqual(Catalog.service("sheet-90")?.method, .apiKey)
        XCTAssertEqual(Catalog.service("sheet-90")?.kind, .subscription)
        XCTAssertFalse(ManualCatalog.all.contains { $0.id == "sheet-90" })
        XCTAssertEqual(Catalog.service("sheet-11")?.method, .statuslineFile)
        XCTAssertEqual(Catalog.service("sheet-187")?.name, "Kindroid")
        XCTAssertTrue(ManualCatalog.all.allSatisfy { $0.method == .manual && $0.apiKeyHelp == nil })
    }

    func testManualObservationNeverInventsResetAndIsTimestamped() throws {
        let record = try ManualObservation(remaining: 0, unit: "credits", observedAt: observed,
                                           source: "公式のUsage画面", now: later)
        XCTAssertNil(record.resetsAt)
        XCTAssertEqual(record.snapshot.credit?.amount, 0)
        XCTAssertNil(record.snapshot.credit?.resetsAt)
        XCTAssertEqual(record.snapshot.fetchedAt, observed)
        XCTAssertTrue(record.snapshot.credit?.note?.contains("手動記録") == true)
    }

    func testManualValidationRejectsInvalidAndFutureData() {
        XCTAssertThrowsError(try ManualObservation(remaining: -1, unit: "credits", observedAt: observed,
                                                    source: "公式", now: later))
        XCTAssertThrowsError(try ManualObservation(remaining: .infinity, unit: "credits", observedAt: observed,
                                                    source: "公式", now: later))
        XCTAssertThrowsError(try ManualObservation(remaining: 1, unit: "", observedAt: observed,
                                                    source: "公式", now: later))
        XCTAssertThrowsError(try ManualObservation(remaining: 1, unit: "USD", observedAt: observed,
                                                    source: "", now: later))
        XCTAssertThrowsError(try ManualObservation(remaining: 1, unit: "USD",
                                                    observedAt: later.addingTimeInterval(601),
                                                    source: "公式", now: later))
        XCTAssertThrowsError(try ManualObservation(remaining: 1, unit: "USD", observedAt: observed,
                                                    resetsAt: observed.addingTimeInterval(-1),
                                                    source: "公式", now: later))
    }

    func testCSVImportParsesEscapedSourceAndMultipleRows() throws {
        let csv = #"""
        remaining,unit,observed_at,reset_at,source
        12,credits,2026-11-05T12:00:00Z,,"公式, Billing"
        0,requests,2026-11-05T12:01:00Z,2026-11-06T00:00:00Z,"Usage ""Quota"""
        """#
        let records = try ManualImport.parseCSV(csv, now: later.addingTimeInterval(300))
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].source, "公式, Billing")
        XCTAssertNil(records[0].resetsAt)
        XCTAssertEqual(records[1].remaining, 0)
        XCTAssertEqual(records[1].source, #"Usage "Quota""#)
        XCTAssertNotNil(records[1].resetsAt)
    }

    func testCSVRejectsMissingFieldsAndMalformedRows() {
        XCTAssertThrowsError(try ManualImport.parseCSV("remaining,unit,source\n1,USD,usage", now: later))
        XCTAssertThrowsError(try ManualImport.parseCSV("remaining,unit,observed_at,source\n-5,USD,2026-11-05T12:00:00Z,official",
                                                      now: later))
        XCTAssertThrowsError(try ManualImport.parseCSV("remaining,unit,observed_at,source\n1,USD,not-a-date,official",
                                                      now: later))
        XCTAssertThrowsError(try ManualImport.parseCSV("""
        remaining,unit,observed_at,source
        1,USD,2026-11-05T12:00:00Z,"bad,
        """, now: later))
    }
}


final class AntigravityStatuslineTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testParsesOfficialQuotaStatuslineAndKeepsResetTime() throws {
        let json = #"{"gemini-weekly":{"remaining_fraction":0.9378,"reset_time":"2026-07-06T07:50:32Z","reset_in_seconds":560580},"claude-daily":{"remaining_amount":12,"reset_time":"2026-07-06T08:00:00Z"}}"#
        let snapshot = try AntigravityStatusline.parse(data(json), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.windows.count, 2)
        let weekly = try XCTUnwrap(snapshot.windows.first { $0.label == "gemini-weekly" })
        XCTAssertEqual(weekly.usedPercent ?? -1, 6.22, accuracy: 0.001)
        XCTAssertEqual(weekly.remainingPercent ?? -1, 93.78, accuracy: 0.001)
        XCTAssertEqual(weekly.resetsAt, Date(timeIntervalSince1970: 1_783_324_232))
        let daily = try XCTUnwrap(snapshot.windows.first { $0.label == "claude-daily" })
        XCTAssertNil(daily.usedPercent)
        XCTAssertEqual(daily.remainingCount, 12)
        XCTAssertNil(snapshot.credit)
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testParsesWrappedQuotaAndSkipsDisabledBuckets() throws {
        let wrapped = #"{"quota":{"disabled-model":{"disabled":true},"weekly":{"remaining_fraction":0.5}}}"#
        let snapshot = try AntigravityStatusline.parse(data(wrapped), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPercent ?? -1, 50, accuracy: 0.001)
        XCTAssertNil(snapshot.windows[0].resetsAt)
    }

    func testRejectsMissingMalformedAndInvalidQuotaValues() {
        for json in [
            "{}",
            #"{"quota":{}}"#,
            #"{"quota":{"weekly":{"remaining_fraction":1.1}}}"#,
            #"{"weekly":{"remaining_fraction":-0.1}}"#,
            #"{"weekly":{"remaining_fraction":0.5,"reset_time":"later"}}"#,
            #"{"weekly":{"remaining_fraction":"unknown"}}"#,
            #"{"weekly":{"disabled":true}}"#,
            "not json"
        ] {
            XCTAssertThrowsError(try AntigravityStatusline.parse(data(json), fetchedAt: fetchedAt), "Should reject: \(json)")
        }
    }
}


final class V0BillingTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testParsesRemainingCreditsAndBillingCycleEnd() throws {
        let json = #"{"object":"plan","plan":"plus","billingCycle":{"start":1717430400,"end":1720108800},"balance":{"remaining":12000,"total":20000}}"#
        let snapshot = try V0Billing.parse(Data(json.utf8), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.credit?.amount, 12000)
        XCTAssertEqual(snapshot.credit?.currency, "credits")
        XCTAssertEqual(snapshot.credit?.resetsAt, Date(timeIntervalSince1970: 1_720_108_800))
        XCTAssertEqual(snapshot.credit?.note, "v0 plus")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertTrue(snapshot.windows.isEmpty)
    }

    func testRejectsMissingMalformedAndNegativeBalance() {
        for json in [
            "{}",
            #"{"balance":{}}"#,
            #"{"balance":{"remaining":-1}}"#,
            #"{"balance":{"remaining":"unknown"}}"#,
            #"{"billingCycle":{"end":"later"},"balance":{"remaining":1}}"#,
            "not json"
        ] {
            XCTAssertThrowsError(try V0Billing.parse(Data(json.utf8), fetchedAt: fetchedAt))
        }
    }
}


final class TavilyUsageTests: XCTestCase {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    func d(_ s: String) -> Data { s.data(using: .utf8)! }
    func testParsesOfficialKeyPlanAndPaygoUsage() throws {
        let json = #"{"key":{"usage":150,"limit":1000},"account":{"plan_usage":500,"plan_limit":15000,"paygo_usage":25,"paygo_limit":100}}"#
        let snapshot = try TavilyUsage.parse(d(json), fetchedAt: at)
        XCTAssertEqual(snapshot.windows.count, 3)
        XCTAssertEqual(snapshot.windows[0].remainingCount, 850)
        XCTAssertEqual(snapshot.windows[1].usedPercent ?? 0, 100.0 / 30.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.windows[2].remainingCount, 75)
    }
    func testRejectsResponseWithoutUsageLimits() {
        XCTAssertThrowsError(try TavilyUsage.parse(d(#"{"key":{"usage":3,"limit":null},"account":{}}"#), fetchedAt: at))
        XCTAssertThrowsError(try TavilyUsage.parse(d("not json"), fetchedAt: at))
    }
}



final class ApolloCreditsTests: XCTestCase {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    func d(_ s: String) -> Data { s.data(using: .utf8)! }

    func testParsesOfficialCreditPoolsAndCycleEnd() throws {
        let fixture = #"{"credit_usage_stats":{"lead_credit":{"limit":10000,"consumed":2500,"left_over":7500},"ai_credit":{"limit":2000,"consumed":75,"left_over":1925},"dialer":{"limit":500,"consumed":12,"left_over":488},"excluded":{"limit":0,"consumed":0,"left_over":0}},"current_credit_cycle":{"start_date":"2026-04-01T00:00:00.000Z","end_date":"2026-05-01T00:00:00.000Z"}}"#
        let snapshot = try ApolloCredits.parse(d(fixture), fetchedAt: at)
        XCTAssertEqual(snapshot.windows.count, 3)
        let lead = try XCTUnwrap(snapshot.windows.first { $0.label == "リードクレジット" })
        XCTAssertEqual(lead.remainingCount, 7500)
        XCTAssertEqual(lead.usedPercent, 25)
        XCTAssertEqual(lead.resetsAt, Date(timeIntervalSince1970: 1_777_593_600))
        XCTAssertEqual(snapshot.windows.first { $0.label.contains("分") }?.remainingCount, 488)
    }

    func testRejectsMissingMalformedAndNegativeCreditFields() {
        for fixture in [
            "{}",
            #"{"credit_usage_stats":{"lead_credit":{"limit":5,"consumed":2}},"current_credit_cycle":{}}"#,
            #"{"credit_usage_stats":{"lead_credit":{"limit":5,"consumed":-2,"left_over":7}},"current_credit_cycle":{}}"#,
            "not json"
        ] {
            XCTAssertThrowsError(try ApolloCredits.parse(d(fixture), fetchedAt: at))
        }
    }
}


final class PoeBalanceTests: XCTestCase {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    func d(_ s: String) -> Data { s.data(using: .utf8)! }

    func testParsesOfficialCurrentPointBalance() throws {
        let snapshot = try PoeBalance.parse(d(#"{"current_point_balance":1500}"#), fetchedAt: at)
        XCTAssertEqual(snapshot.credit?.amount, 1500)
        XCTAssertEqual(snapshot.credit?.currency, "points")
        XCTAssertEqual(snapshot.fetchedAt, at)
    }

    func testRejectsMissingMalformedNegativeAndFractionalBalance() {
        for fixture in ["{}", #"{"current_point_balance":-1}"#, #"{"current_point_balance":1.5}"#, "not json"] {
            XCTAssertThrowsError(try PoeBalance.parse(d(fixture), fetchedAt: at))
        }
    }
}


final class ElicitUsageTests: XCTestCase {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    func d(_ s: String) -> Data { s.data(using: .utf8)! }

    func testParsesPlanUsageAndCappedExtraUsage() throws {
        let fixture = #"{"hasUsageRemaining":true,"percentUsed":42.5,"periodStart":"2026-11-01T00:00:00Z","periodEnd":"2026-12-01T00:00:00Z","extraUsage":{"limitUsdCents":500,"spentUsdCents":125}}"#
        let snapshot = try ElicitUsage.parse(d(fixture), fetchedAt: at)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 42.5)
        XCTAssertEqual(snapshot.windows.first?.resetsAt, Date(timeIntervalSince1970: 1_796_083_200))
        XCTAssertEqual(snapshot.credit?.amount, 3.75)
        XCTAssertEqual(snapshot.credit?.currency, "USD")
    }

    func testParsesUncappedExtraUsageWithoutInventingRemainingBalance() throws {
        let fixture = #"{"hasUsageRemaining":false,"percentUsed":100,"periodStart":"","periodEnd":"","extraUsage":{"limitUsdCents":null,"spentUsdCents":250}}"#
        let snapshot = try ElicitUsage.parse(d(fixture), fetchedAt: at)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 100)
        XCTAssertNil(snapshot.credit)
    }

    func testRejectsMissingMalformedAndInvalidUsage() {
        for fixture in [
            "{}",
            #"{"hasUsageRemaining":true,"percentUsed":101,"periodEnd":"","extraUsage":null}"#,
            #"{"hasUsageRemaining":true,"percentUsed":4,"periodEnd":"","extraUsage":{"limitUsdCents":20}}"#,
            "not json"
        ] {
            XCTAssertThrowsError(try ElicitUsage.parse(d(fixture), fetchedAt: at))
        }
    }
}


final class HeadshotProCreditsTests: XCTestCase {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    func d(_ s: String) -> Data { s.data(using: .utf8)! }

    func testParsesOrganizationCreditBalance() throws {
        let snapshot = try HeadshotProCredits.parse(d(#"{"success":true,"credits":100}"#), fetchedAt: at)
        XCTAssertEqual(snapshot.credit?.amount, 100)
        XCTAssertEqual(snapshot.credit?.currency, "credits")
        XCTAssertEqual(snapshot.fetchedAt, at)
    }

    func testRejectsMissingMalformedErrorAndInvalidCredits() {
        for fixture in [
            "{}",
            #"{"success":false,"credits":100}"#,
            #"{"success":true}"#,
            #"{"success":true,"credits":-1}"#,
            #"{"success":true,"credits":1.5}"#,
            "not json"
        ] {
            XCTAssertThrowsError(try HeadshotProCredits.parse(d(fixture), fetchedAt: at))
        }
    }
}
