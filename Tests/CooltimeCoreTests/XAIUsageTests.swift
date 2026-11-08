import XCTest
@testable import CooltimeCore

final class XAIUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testResolvesTeamScopeAndRejectsOtherScopes() throws {
        XCTAssertEqual(try XAIUsage.teamID(from: data(#"{"scope":"SCOPE_TEAM","scopeId":"team-123","teamId":"old"}"#)), "team-123")
        XCTAssertThrowsError(try XAIUsage.teamID(from: data(#"{"scope":"SCOPE_ORGANIZATION","scopeId":"org-123"}"#)))
        XCTAssertThrowsError(try XAIUsage.teamID(from: data(#"{"teamId":"legacy-only"}"#)))
        XCTAssertThrowsError(try XAIUsage.teamID(from: data("not json")))
    }

    func testBuildsCurrentUTCMonthUsageRequest() throws {
        XCTAssertEqual(XAIUsage.usageURL(teamID: "team-123"), "https://management-api.x.ai/v1/billing/teams/team-123/usage")
        let body = try JSONSerialization.jsonObject(with: XAIUsage.usageRequestBody(now: now)) as! [String: Any]
        let request = body["analyticsRequest"] as! [String: Any]
        let range = request["timeRange"] as! [String: String]
        XCTAssertEqual(range["startTime"], "2027-01-01 00:00:00")
        XCTAssertEqual(range["endTime"], "2027-01-15 08:00:00")
        XCTAssertEqual(range["timezone"], "Etc/GMT")
        XCTAssertEqual(request["timeUnit"] as? String, "TIME_UNIT_DAY")
    }

    func testParsesMonthlyUSDReportedCostWithoutInventingRemainingQuota() throws {
        let fixture = #"{"limitReached":false,"timeSeries":[{"group":["Chat grok-4.7"],"dataPoints":[{"timestamp":"2027-01-01T00:00:00Z","values":[0.25]},{"timestamp":"2027-01-02T00:00:00Z","values":[0.75]}]},{"group":["Image"],"dataPoints":[{"timestamp":"2027-01-01T00:00:00Z","values":[1]}]}]}"#
        let snapshot = try XAIUsage.parse(data(fixture), fetchedAt: now)
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.reportedAmount ?? -1, 2, accuracy: 0.0001)
        XCTAssertEqual(window.reportedUnit, "USD")
        XCTAssertNil(window.usedPercent)
        XCTAssertNil(window.remainingCount)
        XCTAssertNil(window.resetsAt)
    }

    func testRejectsIncompleteMalformedAndNegativeUsage() {
        let fixtures = [
            #"{"limitReached":true,"timeSeries":[]}"#,
            #"{"limitReached":false}"#,
            #"{"limitReached":false,"timeSeries":[{"dataPoints":[{"values":[]}]}]}"#,
            #"{"limitReached":false,"timeSeries":[{"dataPoints":[{"values":[-1]}]}]}"#,
            "not json"
        ]
        for fixture in fixtures {
            XCTAssertThrowsError(try XAIUsage.parse(data(fixture), fetchedAt: now))
        }
    }

    func testEmptyCompleteReportIsZeroCost() throws {
        let snapshot = try XAIUsage.parse(data(#"{"limitReached":false,"timeSeries":[]}"#), fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 0)
    }
}
