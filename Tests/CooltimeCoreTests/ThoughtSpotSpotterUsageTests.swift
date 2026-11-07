import Foundation
import XCTest
@testable import CooltimeCore

final class ThoughtSpotSpotterUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    func testTenantHostAndOnlyAuthenticatedUser() throws {
        let config = try ThoughtSpotSpotterUsage.configuration(from: "sample.thoughtspot.cloud|sample-token")
        XCTAssertEqual(config.url, "https://sample.thoughtspot.cloud/api/rest/2.0/ai/usage-data/user")
        XCTAssertEqual(config.token, "sample-token")
        for invalid in ["sample.thoughtspot.cloud.example.org", "sample.thoughtspot.cloud:443",
                        "https://sample.thoughtspot.cloud", "sample.thoughtspot.cloud@localhost"] {
            XCTAssertThrowsError(try ThoughtSpotSpotterUsage.configuration(from: "\(invalid)|sample-token"))
        }
    }

    func testOfficialRemainingAndLimitFlags() throws {
        let available = try ThoughtSpotSpotterUsage.parse(report(remaining: 30), fetchedAt: now)
        XCTAssertEqual(available.windows.first?.reportedAmount, 120)
        XCTAssertEqual(available.windows.first?.remainingCount, 30)
        XCTAssertNil(available.windows.first?.resetsAt)

        let exhausted = try ThoughtSpotSpotterUsage.parse(report(remaining: 0, limited: true), fetchedAt: now)
        XCTAssertEqual(exhausted.windows.first?.remainingCount, 0)
        XCTAssertEqual(exhausted.windows.first?.isExhausted, true)
    }

    func testUnlimitedPoolHasUsageAndNoNumericRemaining() throws {
        let snapshot = try ThoughtSpotSpotterUsage.parse(report(unlimited: true), fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 120)
        XCTAssertNil(snapshot.windows.first?.remainingCount)
    }

    func testEmptyMalformedAndConflictingQuotaCannotAppearAsZero() {
        for invalid in [Data("{}".utf8), report(), report(remaining: -1),
                        report(remaining: 0), report(remaining: 30, limited: true),
                        Data(#"{"summary":{"pools":[],"has_unlimited_pool":false,"is_at_limit":false}}"#.utf8)] {
            XCTAssertThrowsError(try ThoughtSpotSpotterUsage.parse(invalid, fetchedAt: now))
        }
        XCTAssertEqual(Catalog.service("sheet-182")?.method, .manual)
        XCTAssertEqual(Catalog.service("thoughtspot-spotter-usage")?.method, .apiKey)
    }

    private func report(remaining: Int? = nil, unlimited: Bool = false, limited: Bool = false) -> Data {
        let left = remaining.map { ",\"total_remaining\":\($0)" } ?? ""
        return Data("""
        {"summary":{"pools":[{"usage":120},{"usage":0}],"total_usage":120,
        "has_unlimited_pool":\(unlimited),"is_at_limit":\(limited)\(left)}}
        """.utf8)
    }
}
