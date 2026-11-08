import Foundation
import XCTest
@testable import CooltimeCore

final class GeminiCLILocalUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPrettyPrintedAppendLogCountsOnlyResponseNumbers() throws {
        let records = """
        {"body":"API response", "attributes":{"event.name":"gemini_cli.api_response","event.timestamp":"2026-11-07T11:00:00.123Z","input_token_count":12,"output_token_count":3,"response_text":"private {text}"}}
        {
          "body": "Other event", "attributes": {"event.name":"gemini_cli.api_request", "input_token_count":999}
        }
        {"attributes":{"event.name":"gemini_cli.api_response","event.timestamp":"2026-11-07T12:00:00Z","input_token_count":0,"output_token_count":7}}
        """
        let snapshot = try GeminiCLILocalUsage.parse(Data(records.utf8), fetchedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.reportedAmount), [12, 10])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.usedPercent == nil && $0.remainingCount == nil && $0.resetsAt == nil })
        XCTAssertFalse(String(describing: snapshot).contains("private"))
    }

    func testMalformedOrMissingNumericResponseIsRejected() {
        for value in ["{\"attributes\":{\"event.name\":\"gemini_cli.api_request\"}}",
                      "{\"attributes\":{\"event.name\":\"gemini_cli.api_response\",\"event.timestamp\":\"2026-11-07T00:00:00Z\",\"input_token_count\":-1,\"output_token_count\":4}}",
                      "{\"attributes\":{\"event.name\":\"gemini_cli.api_response\",\"event.timestamp\":\"2026-11-07T00:00:00Z\",\"input_token_count\":true,\"output_token_count\":4}}",
                      "{\"attributes\":{\"event.name\":\"gemini_cli.api_response\"}}",
                      "{\"unfinished\":true"] {
            XCTAssertThrowsError(try GeminiCLILocalUsage.parse(Data(value.utf8), fetchedAt: now))
        }
    }

    func testCatalogHasAutomaticAndManualAlternatives() {
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "gemini-cli-local-usage" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-12" })
    }
}
