import XCTest
@testable import CooltimeCore

final class MagnificTeamCreditsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")!

    func testRequestUsesCompleteSevenUTCDays() throws {
        let period = MagnificTeamCredits.period(now: now)
        let body = try MagnificTeamCredits.requestBody(period: period)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["start_date"], "2026-11-01")
        XCTAssertEqual(json["end_date"], "2026-11-07")
        XCTAssertEqual(json["granularity"], "day")
    }

    func testSumsDifferentToolRowsIncludingIdenticalValues() throws {
        let fixture = """
        {"data":[{"date":"2026-11-01T00:00:00+00:00","consumptions":[
          {"tool_name":"pikaso-tti-flux-dev","user_uses":45,"user_credits":1800},
          {"tool_name":"pikaso-nano-banana","user_uses":45,"user_credits":1800}]},
          {"date":"2026-11-02T00:00:00Z","consumptions":[
          {"tool_name":"magnific-premium-download","user_uses":10,"user_credits":900}]}]}
        """
        let snapshot = try MagnificTeamCredits.parse(Data(fixture.utf8),
                                                      period: MagnificTeamCredits.period(now: now), fetchedAt: now)
        XCTAssertEqual(snapshot.windows[0].reportedAmount, 4500)
        XCTAssertEqual(snapshot.windows[1].reportedAmount, 100)
        XCTAssertNil(snapshot.windows[0].remainingCount)
        XCTAssertNil(snapshot.credit)
    }

    func testEmptyOfficialReportIsZeroNotBalance() throws {
        let snapshot = try MagnificTeamCredits.parse(Data(#"{"data":[]}"#.utf8),
                                                      period: MagnificTeamCredits.period(now: now), fetchedAt: now)
        XCTAssertEqual(snapshot.windows[0].reportedAmount, 0)
        XCTAssertNil(snapshot.windows[0].remainingCount)
    }

    func testRejectsDuplicateDayNegativeMissingAndOutOfRange() {
        let period = MagnificTeamCredits.period(now: now)
        for json in ["{}", "<html>error</html>",
                     #"{"data":[{"date":"2026-11-08T00:00:00Z","consumptions":[]}]}"#,
                     #"{"data":[{"date":"2026-11-01T00:00:00Z","consumptions":[]},{"date":"2026-11-01T00:00:00Z","consumptions":[]}]}"#,
                     #"{"data":[{"date":"2026-11-01T00:00:00Z","consumptions":[{"tool_name":"x","user_uses":1,"user_credits":-1}]}]}"#,
                     #"{"data":[{"date":"2026-11-01T00:00:00Z","consumptions":[{"tool_name":"x","user_uses":1}]}]}"#] {
            XCTAssertThrowsError(try MagnificTeamCredits.parse(Data(json.utf8), period: period, fetchedAt: now), json)
        }
    }

    func testManualProviderRemains() {
        XCTAssertEqual(Catalog.service("magnific-team-credits")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-43" })
    }
}
