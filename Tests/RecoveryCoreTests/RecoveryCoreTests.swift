import XCTest
@testable import RecoveryCore

final class RecoveryCoreTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    func snap(_ windows: [WindowStatus], credit: CreditBalance? = nil) -> Snapshot {
        Snapshot(serviceID: "x", result: SourceResult(windows: windows, credit: credit), fetchedAt: base)
    }

    // MARK: 時間の表示

    func testRemainingText() {
        XCTAssertEqual(RemainingFormat.text(until: base.addingTimeInterval(43 * 60), now: base), "あと43分")
        XCTAssertEqual(RemainingFormat.text(until: base.addingTimeInterval(2 * 3600 + 13 * 60), now: base), "あと2時間13分")
        XCTAssertEqual(RemainingFormat.text(until: base.addingTimeInterval(3600), now: base), "あと1時間")
        XCTAssertEqual(RemainingFormat.text(until: base.addingTimeInterval(5 * 3600 + 2 * 86400), now: base), "あと2日5時間")
        XCTAssertEqual(RemainingFormat.text(until: base.addingTimeInterval(10), now: base), "あと1分") // 0分とは出さない
    }

    // MARK: 状態の判定

    func testLimitedUsesLatestExhaustedWindow() {
        let s = snap([
            WindowStatus(name: "5時間枠", usedPercent: 100, resetsAt: base.addingTimeInterval(3600)),
            WindowStatus(name: "週の枠", usedPercent: 100, resetsAt: base.addingTimeInterval(86400))
        ])
        XCTAssertEqual(s.state(at: base), .limited(recoversAt: base.addingTimeInterval(86400)))
    }

    func testOnlyExhaustedWindowCounts() {
        let s = snap([
            WindowStatus(name: "5時間枠", usedPercent: 40, resetsAt: base.addingTimeInterval(3600)),
            WindowStatus(name: "週の枠", usedPercent: 100, resetsAt: base.addingTimeInterval(7200))
        ])
        XCTAssertEqual(s.state(at: base), .limited(recoversAt: base.addingTimeInterval(7200)))
    }

    func testPassedResetIsNotMarkedRecovered() {
        let s = snap([WindowStatus(name: "5時間枠", usedPercent: 100, resetsAt: base.addingTimeInterval(60))])
        XCTAssertEqual(s.state(at: base.addingTimeInterval(120)), .resetEstimatePassed(since: base.addingTimeInterval(60)))
    }

    func testAvailableRemaining() {
        let s = snap([WindowStatus(name: "5時間枠", usedPercent: 38, resetsAt: base.addingTimeInterval(3600))])
        XCTAssertEqual(s.state(at: base), .available(remainingPercent: 62))
    }

    func testCreditOnlyAndNoData() {
        let c = CreditBalance(amount: 95.5, currency: "USD")
        XCTAssertEqual(snap([], credit: c).state(at: base), .credit(c))
        XCTAssertEqual(snap([]).state(at: base), .noData)
    }

    func testEarliestRecovery() {
        let a = snap([WindowStatus(name: "a", usedPercent: 100, resetsAt: base.addingTimeInterval(7200))])
        let b = snap([WindowStatus(name: "b", usedPercent: 100, resetsAt: base.addingTimeInterval(600))])
        let ok = snap([WindowStatus(name: "c", usedPercent: 10, resetsAt: base.addingTimeInterval(60))])
        XCTAssertEqual(Aggregator.earliestRecovery([a, b, ok], now: base), base.addingTimeInterval(600))
        XCTAssertNil(Aggregator.earliestRecovery([ok], now: base))
    }

    // MARK: Claude Code のステータスライン

    func testStatuslineParse() throws {
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":1800003600},"seven_day":{"used_percentage":20,"resets_at":1800500000}}}"#
        let r = try StatuslineSource.parse(Data(json.utf8))
        XCTAssertEqual(r.windows.map(\.name), ["5時間枠", "週の枠"])
        XCTAssertEqual(r.windows[0].resetsAt, Date(timeIntervalSince1970: 1_800_003_600))
    }

    func testStatuslineWithoutRateLimitsFails() {
        XCTAssertThrowsError(try StatuslineSource.parse(Data("{}".utf8)))
    }

    // MARK: 各社のAPI

    func testElevenLabs() throws {
        let json = #"{"character_count":10000,"character_limit":10000,"next_character_count_reset_unix":1800003600}"#
        let r = try BalanceProvider.elevenLabs.parse(Data(json.utf8))
        XCTAssertEqual(r.windows[0].usedPercent, 100)
        XCTAssertEqual(r.windows[0].resetsAt, Date(timeIntervalSince1970: 1_800_003_600))
    }

    func testFirecrawlZeroIsLimited() throws {
        let json = #"{"data":{"remainingCredits":0,"billingPeriodEnd":"2027-01-15T00:00:00Z"}}"#
        let r = try BalanceProvider.firecrawl.parse(Data(json.utf8))
        XCTAssertEqual(r.windows[0].usedPercent, 100)
    }

    func testVercelBalanceAsString() throws {
        let r = try BalanceProvider.vercelAIGateway.parse(Data(#"{"balance":"95.50","total_used":"4.5"}"#.utf8))
        XCTAssertEqual(r.credit?.amount, Decimal(string: "95.5"))
    }

    func testOpenRouterWithoutLimitDoesNotInventNumber() {
        XCTAssertThrowsError(try BalanceProvider.openRouter.parse(Data(#"{"data":{"limit_remaining":null}}"#.utf8)))
    }

    func testDeepSeek() throws {
        let r = try BalanceProvider.deepSeek.parse(Data(#"{"balance_infos":[{"currency":"USD","total_balance":"12.00"}]}"#.utf8))
        XCTAssertEqual(r.credit?.currency, "USD")
    }

    // MARK: Codex

    func testCodexParseResetsInSeconds() throws {
        let result: [String: Any] = ["rateLimits": [
            "primary": ["usedPercent": 100, "windowDurationMins": 300, "resetsInSeconds": 1800],
            "secondary": ["usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 1_800_500_000]
        ]]
        let r = try CodexSource.parse(result, now: base)
        XCTAssertEqual(r.windows[0].name, "5時間枠")
        XCTAssertEqual(r.windows[0].resetsAt, base.addingTimeInterval(1800))
        XCTAssertEqual(r.windows[1].name, "週の枠")
    }

    func testCodexWindowWithoutResetIsDropped() {
        let result: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 100]]]
        XCTAssertThrowsError(try CodexSource.parse(result))
    }
}
