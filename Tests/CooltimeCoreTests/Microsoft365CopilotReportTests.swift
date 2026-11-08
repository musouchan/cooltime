import XCTest
@testable import CooltimeCore

final class Microsoft365CopilotReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_491_200)
    private let upn = "alice@example.com"
    private let heading = "Report Refresh Date,User Principal Name,Display Name,Report Period,Prompts submitted for all apps\r\n"

    func testReadsExactLicensedUserFromV2Report() throws {
        let csv = heading + "2026-11-06,bob@example.com,\"Bob, Jr\",7,9\r\n2026-11-06,alice@example.com,Alice,7,23\r\n"
        let snapshot = try Microsoft365CopilotReport.parse(Data(csv.utf8), principalName: upn, fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 23)
        XCTAssertEqual(snapshot.windows.first?.reportedUnit, "prompts")
        XCTAssertNil(snapshot.windows.first?.remainingCount)
        XCTAssertNil(snapshot.windows.first?.resetsAt)
        XCTAssertNil(snapshot.credit)
    }

    func testRequiresTenantAndUser() throws {
        XCTAssertNoThrow(try Microsoft365CopilotReport.configuration(from: "11111111-2222-3333-4444-555555555555|alice@example.com"))
        for config in ["tenant|alice@example.com", "11111111-2222-3333-4444-555555555555|alice", "11111111-2222-3333-4444-555555555555|a@b|extra"] {
            XCTAssertThrowsError(try Microsoft365CopilotReport.configuration(from: config))
        }
    }

    func testRejectsMissingUserAnonymizedReportAndPartialCSV() {
        for csv in [heading + "2026-11-06,bob@example.com,Bob,7,5\n",
                    heading + "2026-11-06,ANON123,Alice,7,5\n",
                    heading + "2026-11-06,alice@example.com,Alice,7,\n",
                    heading + "2026-11-06,alice@example.com,Alice,7,-3\n",
                    heading + "2026-11-06,alice@example.com,\"Alice,7,5\n",
                    heading + "2026-11-06,alice@example.com,Alice,30,5\n",
                    heading + "2026-11-06,alice@example.com,Alice,7,5\n2026-11-06,alice@example.com,Alice,7,5\n",
                    "<html>error</html>"] {
            XCTAssertThrowsError(try Microsoft365CopilotReport.parse(Data(csv.utf8), principalName: upn, fetchedAt: now), csv)
        }
    }

    func testManualEntryPreserved() {
        XCTAssertEqual(Catalog.service("microsoft365-copilot-report")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-118" })
    }
}
