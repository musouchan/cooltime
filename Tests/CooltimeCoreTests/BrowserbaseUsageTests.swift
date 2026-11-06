import XCTest
@testable import CooltimeCore

final class BrowserbaseUsageTests: XCTestCase {
    func testReturnsProjectUsageAndNoBalance() throws {
        let date = Date(timeIntervalSince1970: 0)
        let data = Data(#"{"browserMinutes":0,"proxyBytes":2500000}"#.utf8)
        let result = try BrowserbaseUsage.parse(data, fetchedAt: date)
        XCTAssertEqual(result, Snapshot(windows: [
            UsageWindow(label: "ブラウザー利用", reportedAmount: 0, reportedUnit: "分"),
            UsageWindow(label: "プロキシ転送量", reportedAmount: 2_500_000, reportedUnit: "B"),
        ], fetchedAt: date))
    }

    func testRejectsInvalidAndMissingMeasurements() {
        for json in [#"{"browserMinutes":-1,"proxyBytes":0}"#, #"{"browserMinutes":2}"#,
                     #"{"browserMinutes":0,"proxyBytes":"10"}"#, #"{"browserMinutes":0,"proxyBytes":9007199254740992}"#] {
            XCTAssertThrowsError(try BrowserbaseUsage.parse(Data(json.utf8), fetchedAt: Date()), json)
        }
    }

    func testProjectConfigurationUsesFixedOfficialHost() throws {
        let config = try BrowserbaseUsage.configuration(from: " test-id | demo_key ")
        XCTAssertEqual(config.url, "https://api.browserbase.com/v1/projects/test-id/usage")
        XCTAssertEqual(config.apiKey, "demo_key")
        for input in ["key", "|key", "test|", "../test|key", "id?x=y|key", "test|demo\r\nkey"] {
            XCTAssertThrowsError(try BrowserbaseUsage.configuration(from: input), input)
        }
    }
}
