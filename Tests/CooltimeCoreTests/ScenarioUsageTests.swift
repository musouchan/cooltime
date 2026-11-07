import XCTest
@testable import CooltimeCore

final class ScenarioUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func data(_ text: String) -> Data { Data(text.utf8) }

    private let valid = #"""
    {
      "limits":{"creativeUnits":1000},
      "oneShotCreativeUnits":[
        {"amount":100,"remaining":60,"createdAt":"2026-10-01T00:00:00Z","expiration":"2027-10-01T00:00:00Z","updatedAt":"2026-11-01T00:00:00Z"},
        {"amount":25,"remaining":10,"createdAt":"2026-10-02T00:00:00.000Z","expiration":"2027-10-02T00:00:00.000Z","updatedAt":"2026-11-02T00:00:00.000Z"}
      ],
      "period":{"start":"2026-11-01T00:00:00Z","end":"2026-12-01T00:00:00Z"},
      "plan":"cu-pro",
      "values":{"creativeUnits":250}
    }
    """#

    func testParsesExactPlanUsageAndOneShotBalance() throws {
        let snapshot = try ScenarioUsage.parse(data(valid), fetchedAt: now)
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.label, "請求期間のプランCU")
        XCTAssertEqual(window.usedPercent ?? -1, 25, accuracy: 0.0001)
        XCTAssertEqual(window.remainingCount, 750)
        XCTAssertEqual(window.reportedAmount, 250)
        XCTAssertEqual(window.reportedUnit, "CU")
        XCTAssertEqual(window.resetsAt, ISO8601DateFormatter().date(from: "2026-12-01T00:00:00Z"))
        XCTAssertEqual(snapshot.credit?.amount, 70)
        XCTAssertEqual(snapshot.credit?.currency, "CU")
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testExplicitZeroAndOverageRemainFacts() throws {
        let zero = valid.replacingOccurrences(of: #""creativeUnits":250"#, with: #""creativeUnits":0"#)
        let zeroSnapshot = try ScenarioUsage.parse(data(zero), fetchedAt: now)
        XCTAssertEqual(zeroSnapshot.windows.first?.remainingCount, 1000)
        XCTAssertEqual(zeroSnapshot.windows.first?.usedPercent, 0)

        let over = valid.replacingOccurrences(of: #""creativeUnits":250"#, with: #""creativeUnits":1250"#)
        let overSnapshot = try ScenarioUsage.parse(data(over), fetchedAt: now)
        XCTAssertEqual(overSnapshot.windows.first?.remainingCount, 0)
        XCTAssertEqual(overSnapshot.windows.first?.usedPercent, 125)
        XCTAssertEqual(overSnapshot.windows.first?.reportedAmount, 1250)
    }

    func testBuildsAllowlistedURLAndBasicAuthentication() throws {
        let config = try ScenarioUsage.configuration(from: "team_abc-1|key-id|secret-value")
        XCTAssertEqual(try ScenarioUsage.url(teamID: config.teamID),
                       "https://api.cloud.scenario.com/v1/teams/team_abc-1/limits")
        XCTAssertEqual(config.authorization,
                       "Basic " + Data("key-id:secret-value".utf8).base64EncodedString())
    }

    func testRejectsMalformedConfigurationAndHostInjection() {
        for value in ["", "team|key", "team||secret", "../teams/x|key|secret",
                      "team|key|secret|extra", "team|key\nInjected|secret"] {
            XCTAssertThrowsError(try ScenarioUsage.configuration(from: value), value)
        }
        XCTAssertThrowsError(try ScenarioUsage.url(teamID: "team/../../example"))
    }

    func testRejectsMalformedAndInvalidResponses() {
        let fixtures = [
            "{}",
            #"{"error":"unauthorized"}"#,
            valid.replacingOccurrences(of: #""creativeUnits":1000"#, with: #""creativeUnits":-1"#),
            valid.replacingOccurrences(of: #""remaining":60"#, with: #""remaining":101"#),
            valid.replacingOccurrences(of: #""end":"2026-12-01T00:00:00Z""#, with: #""end":"bad""#),
            valid.replacingOccurrences(of: #""plan":"cu-pro""#, with: #""plan":"""#),
            "<html>error</html>"
        ]
        for fixture in fixtures {
            XCTAssertThrowsError(try ScenarioUsage.parse(data(fixture), fetchedAt: now), fixture)
        }
    }

    func testKeepsManualEntry() {
        XCTAssertEqual(Catalog.service("scenario-cu-usage")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-174" })
    }
}
