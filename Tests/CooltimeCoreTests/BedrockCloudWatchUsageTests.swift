import XCTest
@testable import CooltimeCore

final class BedrockCloudWatchUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testParsesExactCloudWatchSums() throws {
        let json = #"{"MetricDataResults":[{"Id":"input","Values":[10,20],"StatusCode":"Complete"},{"Id":"output","Values":[3,4],"StatusCode":"Complete"},{"Id":"invocations","Values":[1,2],"StatusCode":"Complete"}]}"#
        let period = BedrockCloudWatchUsage.previousSevenDays(now: now)
        let snapshot = try BedrockCloudWatchUsage.parse(Data(json.utf8), period: period, fetchedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.reportedAmount), [30, 7, 3])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.remainingCount == nil && $0.resetsAt == nil })
    }

    func testPreservesExplicitZeroUsage() throws {
        let json = #"{"MetricDataResults":[{"Id":"input","Values":[],"StatusCode":"Complete"},{"Id":"output","Values":[],"StatusCode":"Complete"},{"Id":"invocations","Values":[],"StatusCode":"Complete"}]}"#
        let snapshot = try BedrockCloudWatchUsage.parse(Data(json.utf8),
            period: BedrockCloudWatchUsage.previousSevenDays(now: now), fetchedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.reportedAmount), [0, 0, 0])
    }

    func testRejectsIncompleteDuplicateAndNegativeMetrics() {
        let period = BedrockCloudWatchUsage.previousSevenDays(now: now)
        for json in [
            #"{"MetricDataResults":[]}"#,
            #"{"MetricDataResults":[{"Id":"input","Values":[1],"StatusCode":"PartialData"},{"Id":"output","Values":[1],"StatusCode":"Complete"},{"Id":"invocations","Values":[1],"StatusCode":"Complete"}]}"#,
            #"{"MetricDataResults":[{"Id":"input","Values":[-1],"StatusCode":"Complete"},{"Id":"output","Values":[1],"StatusCode":"Complete"},{"Id":"invocations","Values":[1],"StatusCode":"Complete"}]}"#
        ] {
            XCTAssertThrowsError(try BedrockCloudWatchUsage.parse(Data(json.utf8), period: period, fetchedAt: now))
        }
    }

    func testConfigurationAndQueryRejectInjection() throws {
        let config = try BedrockCloudWatchUsage.configuration(from: "work|us-east-1|anthropic.claude-3-sonnet")
        XCTAssertEqual(config.modelID, "anthropic.claude-3-sonnet")
        let query = try BedrockCloudWatchUsage.queryJSON(modelID: config.modelID)
        XCTAssertTrue(query.contains("InputTokenCount"))
        for value in ["", "work|us-east-1", "bad;profile|us-east-1|model",
                      "work|us-east-1|model\nInjected"] {
            XCTAssertThrowsError(try BedrockCloudWatchUsage.configuration(from: value))
        }
    }

    func testKeepsManualEntry() {
        XCTAssertEqual(Catalog.service("aws-bedrock-usage")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-100" })
    }
}
