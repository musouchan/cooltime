import XCTest
@testable import CooltimeCore

final class CloudflareGatewayUsageTests: XCTestCase {
    private let at = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
    private let accountID = "0123456789abcdef0123456789abcdef"
    private var period: DailyUsagePeriod { .previousSevenDays(now: at, lagHours: 24) }

    func testReadsDailyUSDUsageFromAccountScopedEndpoint() throws {
        let config = try CloudflareGatewayUsage.configuration(from: "\(accountID)|read-token")
        let url = try XCTUnwrap(URLComponents(string: CloudflareGatewayUsage.url(config: config, period: period)))
        let start = Int64(period.start.timeIntervalSince1970) * 1000
        let end = Int64(period.end.timeIntervalSince1970) * 1000
        XCTAssertEqual(url.host, "api.cloudflare.com")
        XCTAssertEqual(url.path, "/client/v4/accounts/\(accountID)/ai-gateway/billing/usage-history")
        XCTAssertEqual(url.queryItems?.first { $0.name == "start_time" }?.value, String(start))
        XCTAssertEqual(url.queryItems?.first { $0.name == "end_time" }?.value, String(end))
        XCTAssertEqual(url.queryItems?.first { $0.name == "value_grouping_window" }?.value, "day")
        let rows = "{\"start_time\":\(start),\"end_time\":\(start + 86_400_000),\"aggregated_value\":2.5},"
                 + "{\"start_time\":\(end - 86_400_000),\"end_time\":\(end - 1),\"aggregated_value\":1.25}"
        let snapshot = try CloudflareGatewayUsage.parse(report(rows), period: period, fetchedAt: at)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 3.75)
        XCTAssertEqual(snapshot.windows.first?.reportedUnit, "USD")
        XCTAssertNil(snapshot.windows.first?.remainingCount)
        XCTAssertNil(snapshot.credit)
    }

    func testEmptyHistoryAndMalformedOrIncompleteHistory() throws {
        XCTAssertEqual(try CloudflareGatewayUsage.parse(report(""), period: period, fetchedAt: at).windows.first?.reportedAmount, 0)
        let start = Int64(period.start.timeIntervalSince1970) * 1000
        let valid = "{\"start_time\":\(start),\"end_time\":\(start + 86_400_000),\"aggregated_value\":2.5}"
        for data in [report("\(valid),\(valid)"), report(valid, more: true),
                     report(valid.replacingOccurrences(of: "2.5", with: "-2.5")),
                     Data(#"{"success":false,"result":{"history":[]}}"#.utf8), Data("{}".utf8)] {
            XCTAssertThrowsError(try CloudflareGatewayUsage.parse(data, period: period, fetchedAt: at))
        }
    }

    func testRejectsUnsafeConfigurationAndKeepsWorkersAIManualEntry() {
        for config in ["../other|token", "\(accountID)|token\r\ninjected", "\(accountID)|"] {
            XCTAssertThrowsError(try CloudflareGatewayUsage.configuration(from: config))
        }
        XCTAssertEqual(Catalog.service("sheet-99")?.method, .manual)
        XCTAssertEqual(Catalog.service("cloudflare-gateway-usage")?.method, .apiKey)
    }

    private func report(_ rows: String, more: Bool = false) -> Data {
        Data("{\"success\":true,\"result\":{\"history\":[\(rows)]},\"result_info\":{\"has_more\":\(more)}}".utf8)
    }
}
