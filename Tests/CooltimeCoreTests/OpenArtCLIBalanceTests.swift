import Foundation
import XCTest
@testable import CooltimeCore

final class OpenArtCLIBalanceTests: XCTestCase {
    func testExplicitBalanceIncludingZero() throws {
        for value in [0, 125] {
            let result = try OpenArtCLIBalance.parse(Data("{\"credits\":\(value)}".utf8), fetchedAt: .now)
            XCTAssertEqual(result.credit?.amount, Double(value))
            XCTAssertEqual(result.credit?.currency, "credits")
            XCTAssertNil(result.credit?.resetsAt)
        }
    }

    func testMissingOrAmbiguousBalancesFailClosed() {
        for json in ["{}", "{\"credits\":null}", "{\"credits\":true}",
                     "{\"credits\":-1}", "{\"credits\":\"10\"}",
                     "{\"credits\":{\"balance\":10}}", "not json"] {
            XCTAssertThrowsError(try OpenArtCLIBalance.parse(Data(json.utf8), fetchedAt: .now))
        }
    }

    func testManualCatalogRemainsAvailable() {
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "openart-cli-balance" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-45" })
    }
}
