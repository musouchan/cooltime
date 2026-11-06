import XCTest
@testable import CooltimeCore

final class DatadogBitsUsageTests: XCTestCase {
    private let date = ISO8601DateFormatter().date(from: "2026-11-01T04:00:00+09:00")!

    func testUsesOnlyAssistantUsageAtAccountLevel() throws {
        let data = Data(#"{"ai_credits_bits_assistant_ai_credits_agg_sum":2.5,"ai_credits_agg_sum":50,"usage":[]}"#.utf8)
        let result = try DatadogBitsUsage.parse(data, fetchedAt: date)
        XCTAssertEqual(result, Snapshot(windows: [
            UsageWindow(label: "Bits AI Assistant 当月（UTC）", reportedAmount: 2.5, reportedUnit: "credits"),
        ], fetchedAt: date))
    }

    func testRejectsMissingOrInvalidAssistantUsage() {
        for json in [#"{"ai_credits_agg_sum":0}"#, #"{"ai_credits_bits_assistant_ai_credits_agg_sum":null}"#,
                     #"{"ai_credits_bits_assistant_ai_credits_agg_sum":-1}"#, #"{"ai_credits_bits_assistant_ai_credits_agg_sum":"0"}"#] {
            XCTAssertThrowsError(try DatadogBitsUsage.parse(Data(json.utf8), fetchedAt: date), json)
        }
        let zero = #"{"ai_credits_bits_assistant_ai_credits_agg_sum":0}"#
        XCTAssertEqual(try DatadogBitsUsage.parse(Data(zero.utf8), fetchedAt: date).windows.first?.reportedAmount, 0)
    }

    func testConfigurationSelectsAnOfficialSiteAndUTCMonth() throws {
        let config = try DatadogBitsUsage.configuration(from: "AP1|api-key|app-key")
        let raw = try DatadogBitsUsage.url(for: config.site, now: date)
        let url = try XCTUnwrap(URLComponents(string: raw))
        XCTAssertEqual(url.host, "api.ap1.datadoghq.com")
        XCTAssertEqual(url.queryItems?.first, URLQueryItem(name: "start_month", value: "2026-10"))
        XCTAssertEqual(config.apiKey, "api-key")
        XCTAssertEqual(config.applicationKey, "app-key")
        for input in ["bad.example|api-key|app-key", "us1||app-key", "us1|api-key|app\nkey"] {
            XCTAssertThrowsError(try DatadogBitsUsage.configuration(from: input), input)
        }
    }
}
