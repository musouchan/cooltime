import XCTest
@testable import CooltimeCore

final class AzureFoundryMonitorUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func response(input: String = "10", output: String = "5", total: String = "15") -> Data {
        Data("""
        {"value":[
          {"name":{"value":"ProcessedPromptTokens"},"unit":"Count","timeseries":[{"data":[{"timeStamp":"2027-01-08T00:00:00Z","total":\(input)}]}]},
          {"name":{"value":"GeneratedTokens"},"unit":"Count","timeseries":[{"data":[{"timeStamp":"2027-01-08T00:00:00Z","total":\(output)}]}]},
          {"name":{"value":"TokenTransaction"},"unit":"Count","timeseries":[{"data":[{"timeStamp":"2027-01-08T00:00:00Z","total":\(total)}]}]}
        ]}
        """.utf8)
    }

    func testParsesExactTokenTotals() throws {
        let period = AzureFoundryMonitorUsage.previousSevenDays(now: now)
        let snapshot = try AzureFoundryMonitorUsage.parse(response(), period: period, fetchedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.reportedAmount), [10, 5, 15])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.remainingCount == nil && $0.resetsAt == nil })
    }

    func testNullTotalIsNoReportedPointAndZeroIsPreserved() throws {
        let period = AzureFoundryMonitorUsage.previousSevenDays(now: now)
        let snapshot = try AzureFoundryMonitorUsage.parse(response(input: "null", output: "0", total: "0"),
                                                           period: period, fetchedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.reportedAmount), [0, 0, 0])
    }

    func testRejectsMalformedMetrics() {
        let period = AzureFoundryMonitorUsage.previousSevenDays(now: now)
        for data in [Data("{}".utf8), response(input: "-1"), response(total: "\"bad\"")] {
            XCTAssertThrowsError(try AzureFoundryMonitorUsage.parse(data, period: period, fetchedAt: now))
        }
    }

    func testConfigurationBuildsFixedResourceIDAndRejectsInjection() throws {
        let c = try AzureFoundryMonitorUsage.configuration(
            from: "123e4567-e89b-12d3-a456-426614174000|my-group|my-account")
        XCTAssertEqual(c.resourceID,
            "/subscriptions/123e4567-e89b-12d3-a456-426614174000/resourceGroups/my-group/providers/Microsoft.CognitiveServices/accounts/my-account")
        for value in ["", "bad|group|name", "123e4567-e89b-12d3-a456-426614174000|../group|name",
                      "123e4567-e89b-12d3-a456-426614174000|group|name\nInjected"] {
            XCTAssertThrowsError(try AzureFoundryMonitorUsage.configuration(from: value))
        }
    }

    func testKeepsManualEntry() {
        XCTAssertEqual(Catalog.service("azure-foundry-monitor-usage")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-102" })
    }
}
