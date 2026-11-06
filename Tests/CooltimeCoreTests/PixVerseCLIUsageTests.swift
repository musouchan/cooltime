import XCTest
@testable import CooltimeCore

final class PixVerseCLIUsageTests: XCTestCase {
    private let observed = Date(timeIntervalSince1970: 1_793_880_000)

    func testPersonalBalanceUsesReportedTotal() throws {
        let json = #"{"email":"example@example.com","credits":{"daily":10,"membership":20,"bonus":5,"total":45},"workspace":{"workspaceId":0}}"#
        let snapshot = try PixVerseCLIUsage.parse(Data(json.utf8), fetchedAt: observed)
        XCTAssertEqual(snapshot.credit, CreditBalance(amount: 45, currency: "credits", note: "個人ワークスペース"))
        XCTAssertEqual(snapshot.fetchedAt, observed)
    }

    func testTeamBalanceMayBeZero() throws {
        let json = #"{"credits":{"total":0,"used":1200},"workspace":{"workspaceId":42}}"#
        let snapshot = try PixVerseCLIUsage.parse(Data(json.utf8), fetchedAt: observed)
        XCTAssertEqual(snapshot.credit, CreditBalance(amount: 0, currency: "credits", note: "チームの共有枠"))
    }

    func testRejectsMissingOrInvalidBalanceAndWorkspace() {
        for json in [
            "invalid",
            #"{"credits":{"used":10},"workspace":{"workspaceId":0}}"#,
            #"{"credits":{"total":-1},"workspace":{"workspaceId":0}}"#,
            #"{"credits":{"total":"3"},"workspace":{"workspaceId":0}}"#,
            #"{"credits":{"total":9007199254740992},"workspace":{"workspaceId":0}}"#,
            #"{"credits":{"total":0}}"#,
            #"{"credits":{"total":0},"workspace":{"workspaceId":-1}}"#,
        ] {
            XCTAssertThrowsError(try PixVerseCLIUsage.parse(Data(json.utf8), fetchedAt: observed), json)
        }
    }
}
