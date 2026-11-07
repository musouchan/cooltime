import XCTest
@testable import CooltimeCore

final class KreaBalanceTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    func testReadsRawToolResultWithoutInventingReset() throws {
        let raw = #"{"content":[{"type":"text","text":"{\"plan\":{\"name\":\"Test\"},\"compute_units\":{\"total\":42,\"plan\":22,\"purchased\":20,\"free\":0}}"}]}"#
        let snapshot = try KreaBalance.parse(Data(raw.utf8), fetchedAt: at)
        XCTAssertEqual(snapshot.credit?.amount, 42)
        XCTAssertEqual(snapshot.credit?.currency, "compute units")
        XCTAssertNil(snapshot.credit?.resetsAt)
    }

    func testReadsExplicitZeroAndRejectsMissingOrUnrelatedBalance() throws {
        let zero = #"{"structuredContent":{"compute_units":{"total":0}}}"#
        XCTAssertEqual(try KreaBalance.parse(Data(zero.utf8), fetchedAt: at).credit?.amount, 0)
        for fixture in [#"{}"#, #"{"structuredContent":{"balance_micros":9}}"#,
                        #"{"structuredContent":{"compute_units":{}}}"#,
                        #"{"structuredContent":{"compute_units":{"total":-1}}}"#,
                        #"{"isError":true,"structuredContent":{"compute_units":{"total":0}}}"#] {
            XCTAssertThrowsError(try KreaBalance.parse(Data(fixture.utf8), fetchedAt: at))
        }
    }

    func testValidatesProfileAndKeepsManualEntry() throws {
        XCTAssertEqual(try KreaBalance.profile(from: "team-1"), "team-1")
        for value in ["", "../work", "--help", "two words"] {
            XCTAssertThrowsError(try KreaBalance.profile(from: value))
        }
        XCTAssertEqual(Catalog.service("sheet-44")?.method, .manual)
        XCTAssertEqual(Catalog.service("krea-workspace-balance")?.method, .apiKey)
    }
}
