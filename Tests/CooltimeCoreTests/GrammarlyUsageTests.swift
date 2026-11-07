import XCTest
@testable import CooltimeCore

final class GrammarlyUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func page(_ users: String, count: Int, more: Bool = false, cursor: String = "cursor+1") -> Data {
        Data("{\"data\":[\(users)],\"paging\":{\"page_size\":\(count),\"has_more\":\(more),\"next_cursor\":\"\(cursor)\"}}".utf8)
    }

    func testReadsSelectedUserAfterFetchingAllPages() async throws {
        let period = DailyUsagePeriod.previousSevenDays(now: now, lagHours: 48)
        var requests: [String] = []
        let result = try await GrammarlyUsage.fetch(userID: 7, period: period, fetchedAt: now) { url in
            requests.append(url)
            if requests.count == 1 {
                return page(#"{"id":8,"prompt_count":99}"#, count: 1, more: true)
            }
            return page(#"{"id":7,"prompt_count":14}"#, count: 1)
        }
        XCTAssertEqual(result.windows.first?.reportedAmount, 14)
        XCTAssertEqual(result.windows.first?.reportedUnit, "prompts")
        XCTAssertNil(result.credit)
        XCTAssertTrue(requests[0].contains("date_from=\(period.firstDay)"))
        XCTAssertTrue(requests[1].contains("cursor=cursor%2B1"))
    }

    func testExplicitZero() async throws {
        let result = try await GrammarlyUsage.fetch(userID: 7,
            period: DailyUsagePeriod.previousSevenDays(now: now, lagHours: 48), fetchedAt: now) { _ in
            page(#"{"id":7,"prompt_count":0}"#, count: 1)
        }
        XCTAssertEqual(result.windows.first?.reportedAmount, 0)
    }

    func testRejectsMalformedAndMissingUserData() async {
        for fixture in [
            page("", count: 0), page(#"{"id":9,"prompt_count":5}"#, count: 1),
            page(#"{"id":7,"prompt_count":-1}"#, count: 1), page(#"{"id":7}"#, count: 1),
            page(#"{"id":7,"prompt_count":1},{"id":7,"prompt_count":2}"#, count: 2),
            page(#"{"id":7,"prompt_count":2}"#, count: 2)
        ] {
            do {
                _ = try await GrammarlyUsage.fetch(userID: 7,
                    period: DailyUsagePeriod.previousSevenDays(now: now, lagHours: 48), fetchedAt: now) { _ in fixture }
                XCTFail("Invalid data produced a snapshot")
            } catch is ParseError {
            } catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testRejectsRepeatedCursorEvenAfterMatchingUser() async {
        var requests = 0
        do {
            _ = try await GrammarlyUsage.fetch(userID: 7,
                period: DailyUsagePeriod.previousSevenDays(now: now, lagHours: 48), fetchedAt: now) { _ in
                requests += 1
                return page("{\"id\":\(requests == 1 ? 7 : 9),\"prompt_count\":10}", count: 1, more: true)
            }
            XCTFail("Incomplete pagination produced a snapshot")
        } catch is ParseError {
            XCTAssertEqual(requests, 2)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testValidatesConfigurationAndEncodesOAuthScope() throws {
        let config = try GrammarlyUsage.configuration("7|client+id|secret&field=x")
        XCTAssertEqual(config.userID, 7)
        let body = String(decoding: GrammarlyUsage.tokenBody(config), as: UTF8.self)
        XCTAssertEqual(body, "grant_type=client_credentials&client_id=client%2Bid&client_secret=secret%26field%3Dx&scope=analytics-api%3Aread")
        for value in ["0|id|secret", "7|id|", "7|id", "7|id|secret\n"] {
            XCTAssertThrowsError(try GrammarlyUsage.configuration(value))
        }
    }

    func testValidatesTokenResponse() throws {
        XCTAssertEqual(try GrammarlyUsage.token(Data(#"{"access_token":"token_1","token_type":"Bearer"}"#.utf8)), "token_1")
        for value in [#"{"error":"invalid_client"}"#, #"{"access_token":"x\r\nInjected","token_type":"Bearer"}"#, #"{"access_token":"x","token_type":"Basic"}"#] {
            XCTAssertThrowsError(try GrammarlyUsage.token(Data(value.utf8)))
        }
    }

    func testKeepsManualEntry() {
        XCTAssertEqual(Catalog.service("grammarly-ai-usage")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-137" })
    }
}
