import Foundation
import XCTest
@testable import CooltimeCore

final class KlingAPIPackageUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    func testOfficialRequestUsesMillisecondsAndReadOnlyEndpoint() throws {
        let url = try XCTUnwrap(URLComponents(string: KlingAPIPackageUsage.url(now: now)))
        XCTAssertEqual(url.host, "api-singapore.klingai.com")
        XCTAssertEqual(url.path, "/account/costs")
        let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["start_time"] ?? nil, "1791408000000")
        XCTAssertEqual(query["end_time"] ?? nil, "1794000000000")
    }

    func testKeepsLivePackagesSeparateAndNeverUsesExpiryAsReset() throws {
        let snapshot = try KlingAPIPackageUsage.parse(response([
            package("a", remaining: "118.5"), package("b", remaining: "20", status: "runOut"),
            package("c", remaining: "50", status: "expired"),
            package("d", remaining: "100", status: "toBeOnline"),
            package("e", remaining: "5", expiry: 1_794_000_000_000)
        ]), fetchedAt: now)
        XCTAssertEqual(snapshot.windows.compactMap(\.remainingCount), [118.5, 0])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.resetsAt == nil })
        XCTAssertNil(snapshot.credit)
    }

    func testErrorsDuplicatesAndNoEffectivePackage() {
        for data in [response([package("a")], code: 1),
                     response([package("a")], payloadCode: 1),
                     response([package("a"), package("a")]),
                     response([package("a", remaining: "-1")]),
                     response([package("a", status: "unknown")]),
                     response([package("a", status: "expired")]),
                     response([]), Data("{}".utf8)] {
            XCTAssertThrowsError(try KlingAPIPackageUsage.parse(data, fetchedAt: now))
        }
    }

    func testManualAndAutomaticEntriesAreSeparate() {
        XCTAssertEqual(Catalog.service("sheet-49")?.method, .manual)
        XCTAssertEqual(Catalog.service("kling-api-package-usage")?.method, .apiKey)
    }

    private func package(_ id: String, remaining: String = "1", status: String = "online",
                         expiry: Int64 = 1_794_100_000_000) -> String {
        """
        {"resource_pack_id":"\(id)","resource_pack_name":"Video \(id)","remaining_quantity":\(remaining),
        "effective_time":1793900000000,"invalid_time":\(expiry),"status":"\(status)"}
        """
    }

    private func response(_ packages: [String], code: Int = 0, payloadCode: Int = 0) -> Data {
        Data("""
        {"code":\(code),"data":{"code":\(payloadCode),"resource_pack_subscribe_infos":[\(packages.joined(separator: ","))]}}
        """.utf8)
    }
}
