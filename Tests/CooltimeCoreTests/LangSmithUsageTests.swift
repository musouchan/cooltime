import XCTest
@testable import CooltimeCore

final class LangSmithUsageTests: XCTestCase {
    private let workspace = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let date = ISO8601DateFormatter().date(from: "2026-11-06T13:00:00Z")!

    private func bucket(_ time: String, count: Int, workspace: UUID? = nil) -> String {
        """
        {"time_bucket":"\(time)","dimensions":{"workspace_id":"\((workspace ?? self.workspace).uuidString)"},"traces":\(count)}
        """
    }

    private func parse(_ buckets: [String]) throws -> Snapshot {
        let json = """
        {"stride":{"days":1,"hours":0},"usage":[\(buckets.joined(separator: ","))]}
        """
        return try LangSmithUsage.parse(Data(json.utf8), workspace: workspace,
                                        period: LangSmithUsage.period(endingBefore: date), fetchedAt: date)
    }

    func testRequestUsesRegionWorkspaceAndUTCDateBoundaries() throws {
        let config = try LangSmithUsage.configuration(from: "eu|\(workspace)|demo-key")
        let period = LangSmithUsage.period(endingBefore: date)
        let rawURL = try LangSmithUsage.url(for: config.region, workspace: config.workspace, period: period)
        let url = try XCTUnwrap(URLComponents(string: rawURL))
        XCTAssertEqual(url.host, "eu.api.smith.langchain.com")
        XCTAssertEqual(url.path, "/api/v1/orgs/current/billing/granular-usage")
        XCTAssertEqual(url.queryItems, [
            URLQueryItem(name: "start_time", value: "2026-10-30T00:00:00Z"),
            URLQueryItem(name: "end_time", value: "2026-11-06T00:00:00Z"),
            URLQueryItem(name: "workspace_ids", value: workspace.uuidString.lowercased()),
            URLQueryItem(name: "group_by", value: "workspace"),
            URLQueryItem(name: "kind", value: "traces"),
        ])
        XCTAssertEqual(config.apiKey, "demo-key")
        XCTAssertThrowsError(try LangSmithUsage.configuration(from: "https://other.invalid|\(workspace)|demo-key"))
    }

    func testReportsOnlyTheSelectedWorkspacesTraceCount() throws {
        let snapshot = try parse([bucket("2026-10-30T00:00:00Z", count: 0),
                                  bucket("2026-11-05T00:00:00.000Z", count: 40)])
        XCTAssertEqual(snapshot, Snapshot(windows: [
            UsageWindow(label: "直近7 UTC日（当日除く）", reportedAmount: 40, reportedUnit: "トレース"),
        ], fetchedAt: date))
    }

    func testRejectsEmptyWrongWorkspaceDuplicateAndOutOfRangeBuckets() {
        let good = bucket("2026-11-05T00:00:00Z", count: 1)
        XCTAssertThrowsError(try parse([]))
        XCTAssertThrowsError(try parse([good, good]))
        XCTAssertThrowsError(try parse([bucket("2026-11-06T00:00:00Z", count: 1)]))
        XCTAssertThrowsError(try parse([bucket("2026-11-05T00:00:00Z", count: -1)]))
        XCTAssertThrowsError(try parse([bucket("2026-11-05T00:00:00Z", count: 1, workspace: UUID())]))
    }
}
