import XCTest
@testable import CooltimeCore

final class KiroEnterpriseUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testSelectsOnlyNewestPerClientReportDay() throws {
        let listing = #"""
        {"Contents":[
          {"Key":"reports/AWSLogs/123/KiroLogs/by_user_analytic/us-east-1/2026/11/07/00/legacy.csv"},
          {"Key":"reports/AWSLogs/123/KiroLogs/user_report/us-east-1/2026/11/06/00/KIRO_IDE_123_user_report_old.csv"},
          {"Key":"reports/AWSLogs/123/KiroLogs/user_report/us-east-1/2026/11/07/00/KIRO_IDE_123_user_report_new.csv"},
          {"Key":"reports/AWSLogs/123/KiroLogs/user_report/us-east-1/2026/11/07/00/KIRO_CLI_123_user_report_new.csv"}
        ]}
        """#
        XCTAssertEqual(try KiroEnterpriseUsage.reportKeys(from: data(listing)), [
            "reports/AWSLogs/123/KiroLogs/user_report/us-east-1/2026/11/07/00/KIRO_CLI_123_user_report_new.csv",
            "reports/AWSLogs/123/KiroLogs/user_report/us-east-1/2026/11/07/00/KIRO_IDE_123_user_report_new.csv"
        ])
    }

    func testSumsSelectedUserAcrossOfficialClientFiles() throws {
        let header = "Date,UserId,Client_Type,Credits_Used,Overage_Cap,Overage_Credits_Used,Overage_Enabled,ProfileId,Subscription_Tier,Total_Messages,New_User,User_Email\n"
        let ide = header + "2026-11-07,user-1,KIRO_IDE,12.5,100,2,true,p1,Pro,20,false,me@example.com\n"
        let cli = header + "2026-11-07,user-1,KIRO_CLI,3.5,100,0,true,p1,Pro,4,false,me@example.com\n"
        let other = header + "2026-11-07,user-2,PLUGIN,99,0,0,false,p1,Pro,4,false,other@example.com\n"
        let snapshot = try KiroEnterpriseUsage.parse(
            csvFiles: [data(ide), data(cli), data(other)],
            userSelector: "me@example.com", fetchedAt: now)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows[0].reportedAmount, 16)
        XCTAssertEqual(snapshot.windows[0].reportedUnit, "credits")
        XCTAssertEqual(snapshot.windows[1].reportedAmount, 2)
        XCTAssertNil(snapshot.windows[0].remainingCount)
        XCTAssertNil(snapshot.windows[0].resetsAt)
        XCTAssertNil(snapshot.credit)
    }

    func testExplicitZeroUsageIsPreserved() throws {
        let csv = """
        Date,UserId,User_Email,Client_Type,Credits_Used,Overage_Credits_Used,Overage_Enabled
        2026-11-07,user-1,me@example.com,PLUGIN,0,0,false
        """
        let snapshot = try KiroEnterpriseUsage.parse(csvFiles: [data(csv)],
                                                     userSelector: "user-1", fetchedAt: now)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].reportedAmount, 0)
    }

    func testRejectsDuplicateRowsMissingColumnsAndWrongDates() {
        let header = "Date,UserId,User_Email,Client_Type,Credits_Used,Overage_Credits_Used,Overage_Enabled\n"
        let row = "2026-11-07,u,e@example.com,KIRO_IDE,1,0,false\n"
        for files in [
            [data(header + row), data(header + row)],
            [data("Date,UserId\n2026-11-07,u\n")],
            [data(header + "2026-02-30,u,e@example.com,KIRO_IDE,1,0,false\n")],
            [data(header + "2026-11-07,u,e@example.com,UNKNOWN,1,0,false\n")],
            [data(header + "2026-11-07,u,e@example.com,KIRO_IDE,-1,0,false\n")]
        ] {
            XCTAssertThrowsError(try KiroEnterpriseUsage.parse(csvFiles: files,
                                                               userSelector: "u", fetchedAt: now))
        }
    }

    func testRejectsMalformedConfigurationAndS3PathInjection() {
        XCTAssertNoThrow(try KiroEnterpriseUsage.configuration(
            from: "work-profile|us-east-1|example-bucket|reports/|user@example.com"))
        for value in ["", "p|r|bucket|prefix", "p;bad|r|bucket|prefix|u",
                      "p|r|ab|prefix|u", "p|r|bucket|../secret|u",
                      "p|r|bucket|prefix|u\nInjected"] {
            XCTAssertThrowsError(try KiroEnterpriseUsage.configuration(from: value), value)
        }
    }

    func testKeepsManualEntry() {
        XCTAssertEqual(Catalog.service("kiro-enterprise-usage")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-16" })
    }
}
