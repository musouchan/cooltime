import Foundation
import XCTest
@testable import CooltimeCore

final class FlairPredictionsUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCountsCompletePagesWithoutInventingCredits() async throws {
        var urls: [String] = []
        let snapshot = try await FlairPredictionsUsage.fetch(fetchedAt: now) { url in
            urls.append(url)
            if urls.count == 1 {
                return Data("{\"predictions\":[{\"id\":\"a\",\"status\":\"succeeded\",\"outputImages\":[\"private\"]}],\"nextPageCursor\":\"a\",\"hasMore\":true}".utf8)
            }
            return Data("{\"predictions\":[{\"id\":\"b\",\"status\":\"failed\"}],\"nextPageCursor\":null,\"hasMore\":false}".utf8)
        }
        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls[1].contains("lastDocId=a"))
        XCTAssertEqual(snapshot.windows[0].reportedAmount, 2)
        XCTAssertNil(snapshot.credit)
        XCTAssertNil(snapshot.windows[0].remainingCount)
        XCTAssertNil(snapshot.windows[0].resetsAt)
        XCTAssertFalse(String(describing: snapshot).contains("private"))
    }

    func testRejectsMissingCursorAndDuplicateJobs() async {
        for json in ["{\"predictions\":[{\"id\":\"a\"}],\"hasMore\":true}",
                     "{\"predictions\":[{\"id\":\"a\"},{\"id\":\"a\"}],\"hasMore\":false}",
                     "{\"predictions\":[],\"hasMore\":true}"] {
            do {
                _ = try await FlairPredictionsUsage.fetch(fetchedAt: now) { _ in Data(json.utf8) }
                XCTFail("Invalid page accepted")
            } catch { }
        }
    }

    func testManualEntryRemainsAvailable() {
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "flair-enterprise-predictions" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-165" })
    }
}
