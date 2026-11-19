import Foundation
import XCTest
@testable import CooltimeCore

final class AutodeskFlexCSVTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSumsOnlySelectedTeamAndProductWithoutInventingBalance() throws {
        let csv = "Team,Product,Day used,Tokens used,Email\nA,AutoCAD,2026-11-01,3,a@example.com\nA,AutoCAD,2026-11-02,\"1,200\",b@example.com\nB,AutoCAD,2026-11-01,9,c@example.com\nA,Revit,2026-11-01,8,d@example.com\n"
        let result = try AutodeskFlexCSV.parse(Data(csv.utf8), team: "A", product: "AutoCAD", fetchedAt: now)
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertEqual(result.windows[0].reportedAmount, 1203)
        XCTAssertNil(result.windows[0].remainingCount)
        XCTAssertNil(result.windows[0].usedPercent)
        XCTAssertNil(result.windows[0].resetsAt)
        XCTAssertNil(result.credit)
        XCTAssertFalse(String(describing: result).contains("a@example.com"))
    }

    func testRejectsWrongExportAndInvalidAmounts() {
        for csv in ["Team,Product,Day used,Access option\nA,AutoCAD,2026-11-01,Tokens\n",
                    "Team,Product,Day used,Tokens used\nA,AutoCAD,2026-11-01,-1\n",
                    "Team,Product,Day used,Tokens used\nA,AutoCAD,2026-11-01,1.5\n",
                    "Team,Product,Day used,Tokens used\nA,AutoCAD,,10\n"] {
            XCTAssertThrowsError(try AutodeskFlexCSV.parse(Data(csv.utf8), team: "A", product: "AutoCAD", fetchedAt: now))
        }
        XCTAssertThrowsError(try AutodeskFlexCSV.parse(Data("Team,Product,Day used,Tokens used\nB,AutoCAD,2026-11-01,3\n".utf8), team: "A", product: "AutoCAD", fetchedAt: now))
    }

    func testManualServiceRemainsAvailable() {
        XCTAssertNotNil(Catalog.automatic.first { $0.id == "autodesk-flex-csv" })
        XCTAssertNotNil(ManualCatalog.all.first { $0.id == "sheet-163" })
    }
}
