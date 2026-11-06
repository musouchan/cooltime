import XCTest
@testable import CooltimeCore

final class OpenCodeGoUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func response(percent: Any = 25, reset: Any = 1_800_003_600_000.0,
                          limited: Any = false, workspace: String = "wrk_demo") throws -> Data {
        let meter: [String: Any] = ["percent": percent, "limited": limited, "resetsAt": reset]
        return try JSONSerialization.data(withJSONObject: ["location": ["directory": "/example"], "data": [
            "workspace": ["id": workspace, "usageURL": "https://example.invalid/ignore"],
            "go": ["rolling": meter, "weekly": meter, "monthly": meter], "budgets": []]])
    }
    func testOfficialUsedPercentAndMilliseconds() throws {
        let snapshot = try OpenCodeGoUsage.parse(response(), workspace: "wrk_demo", fetchedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [25, 25, 25])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [75, 75, 75])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.remainingCount == nil && $0.resetsAt == now.addingTimeInterval(3600) })
        XCTAssertNil(snapshot.credit)
    }
    func testLimitedFlagDoesNotChangeReportedPercent() throws {
        let snapshot = try OpenCodeGoUsage.parse(response(percent: 99.9, limited: true), workspace: "wrk_demo", fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 99.9)
        XCTAssertNil(snapshot.windows.first?.remainingCount)
        XCTAssertTrue(snapshot.windows.allSatisfy(\.isExhausted))
        XCTAssertTrue(snapshot.windows[0].label.contains("制限中"))
    }
    func testRejectsInvalidValuesAndExpiredOrSecondsTimestamp() throws {
        for percent in [-1.0, 101, 1e100] {
            XCTAssertThrowsError(try OpenCodeGoUsage.parse(response(percent: percent), workspace: "wrk_demo", fetchedAt: now))
        }
        for reset in [-1.0, 1_800_003_600, 1_800_000_000_000, 1e100] {
            XCTAssertThrowsError(try OpenCodeGoUsage.parse(response(reset: reset), workspace: "wrk_demo", fetchedAt: now))
        }
        XCTAssertThrowsError(try OpenCodeGoUsage.parse(response(percent: "5"), workspace: "wrk_demo", fetchedAt: now))
        XCTAssertThrowsError(try OpenCodeGoUsage.parse(response(limited: "false"), workspace: "wrk_demo", fetchedAt: now))
    }
    func testRejectsWrongWorkspaceMissingGoAndSignedOut() throws {
        XCTAssertThrowsError(try OpenCodeGoUsage.parse(response(workspace: "other"), workspace: "wrk_demo", fetchedAt: now))
        for json in ["{}", #"{"data":null}"#, #"{"data":{"workspace":{"id":"wrk_demo"},"budgets":[]}}"#,
                     #"{"error":"UnauthorizedError"}"#] {
            XCTAssertThrowsError(try OpenCodeGoUsage.parse(Data(json.utf8), workspace: "wrk_demo", fetchedAt: now))
        }
    }
    func testLoopbackConfigurationAndSecretEncoding() throws {
        let config = try OpenCodeGoUsage.configuration(from: "49374|wrk_demo|example:password")
        XCTAssertEqual(config.url, "http://127.0.0.1:49374/api/experimental/usage/limits")
        XCTAssertEqual(config.workspace, "wrk_demo")
        XCTAssertEqual(config.authorization, "Basic " + Data("opencode:example:password".utf8).base64EncodedString())
        for input in ["443|wrk_demo|pass", "65536|wrk_demo|pass", "https://evil.example|wrk_demo|pass",
                      "49374|../other|pass", "49374|wrk_demo|", "49374|wrk_demo|p\nr", "49374||pass"] {
            XCTAssertThrowsError(try OpenCodeGoUsage.configuration(from: input))
        }
        XCTAssertEqual(Catalog.service("sheet-26")?.method, .manual)
        XCTAssertEqual(Catalog.service("opencode-go-usage")?.method, .apiKey)
    }
    func testOldStoredWindowsRemainDecodable() throws {
        let old = try JSONDecoder().decode(UsageWindow.self, from: Data(#"{"label":"manual","remainingCount":7}"#.utf8))
        XCTAssertNil(old.isLimited)
        XCTAssertEqual(old.remainingCount, 7)
        XCTAssertFalse(old.isExhausted)
        let limited = UsageWindow(label: "official", usedPercent: 99.9, isLimited: true)
        XCTAssertEqual(try JSONDecoder().decode(UsageWindow.self, from: JSONEncoder().encode(limited)), limited)
    }
}
