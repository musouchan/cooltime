import XCTest
@testable import CooltimeCore

final class ZendeskAIExportUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-07T02:00:00Z")!
    private func data(_ string: String) -> Data { Data(string.utf8) }

    func testPreviousCompleteDayAndConfiguration() throws {
        XCTAssertEqual(ZendeskAIExportUsage.exportDay(now: now), "2026-11-06")
        let config = try ZendeskAIExportUsage.configuration(from: "my-org|org_1|bot_2|secret")
        XCTAssertEqual(ZendeskAIExportUsage.endpoint(subdomain: config.subdomain),
                       "https://my-org.zendesk.com/ai-agents/api/data-export/v3/get-signed-urls")
        for value in ["bad.host|org|bot|token", "org|bot|secret", "org|id|bot|with space", "org|id|bot|x\nInjected: yes"] {
            XCTAssertThrowsError(try ZendeskAIExportUsage.configuration(from: value))
        }
    }

    func testSignedURLRequiresOfficialStorageAndMatchingDay() throws {
        let good = "https://storage.googleapis.com/production-eu-ultimateai-backend-data-export/files/bot/conversation_bot_20261106.json?X-Goog-Signature=abc"
        let links = try ZendeskAIExportUsage.signedURLs(data("""
          {"date":"2026-11-06","urls":["\(good)"]}
          """), day: "2026-11-06")
        XCTAssertEqual(links, [good])
        for bad in ["https://evil.test/files/x.json?sig=abc", "http://storage.googleapis.com/files/x.json?sig=abc",
                    "https://storage.googleapis.com.evil.test/files/x.json?sig=abc",
                    "https://storage.googleapis.com/files/x.json", "https://storage.googleapis.com/files/x.json?sig=abc#fragment"] {
            XCTAssertThrowsError(try ZendeskAIExportUsage.signedURLs(
                data("""
                  {"date":"2026-11-06","urls":["\(bad)"]}
                  """), day: "2026-11-06"), bad)
        }
        XCTAssertThrowsError(try ZendeskAIExportUsage.signedURLs(
            data("""
              {"date":"2026-11-05","urls":["\(good)"]}
              """), day: "2026-11-06"))
    }

    func testCountsOnlyProductionVerifiedResolutionsWithoutInventingBalance() throws {
        let json = """
        [{"bot_id":"bot_2","conversation_id":"one","test_mode":false,"resolution_tier":"core_resolution","conversations_data":{"email":"private@example.com"}},
         {"bot_id":"bot_2","conversation_id":"two","test_mode":true,"resolution_tier":"core_resolution"},
         {"bot_id":"bot_2","conversation_id":"three","test_mode":false,"resolution_tier":"contained_resolution"},
         {"bot_id":"bot_2","conversation_id":"four","test_mode":false,"resolution_tier":"assisted_escalation"}]
        """
        let snapshot = try ZendeskAIExportUsage.parse([data(json)], botID: "bot_2", day: "2026-11-06", fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 1)
        XCTAssertNil(snapshot.windows.first?.remainingCount)
        XCTAssertNil(snapshot.windows.first?.usedPercent)
        XCTAssertNil(snapshot.credit)
    }

    func testRejectsWrongBotDuplicateMalformedAndMissingClassification() {
        for json in [
            #"[{"bot_id":"another","conversation_id":"a","test_mode":false,"resolution_tier":"core_resolution"}]"#,
            #"[{"bot_id":"bot","conversation_id":"a","test_mode":false,"resolution_tier":"core_resolution"},{"bot_id":"bot","conversation_id":"a","test_mode":false,"resolution_tier":"core_resolution"}]"#,
            #"[{"bot_id":"bot","conversation_id":"a","test_mode":false}]"#,
            #"[{"bot_id":"bot","conversation_id":"a","test_mode":false,"resolution_tier":"new_tier"}]"#,
            "<html>error</html>"
        ] {
            XCTAssertThrowsError(try ZendeskAIExportUsage.parse([data(json)], botID: "bot", day: "2026-11-06", fetchedAt: now), json)
        }
    }

    func testManualEntryRemainsAvailable() {
        XCTAssertEqual(Catalog.service("zendesk-ai-export-usage")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-129" })
    }
}
