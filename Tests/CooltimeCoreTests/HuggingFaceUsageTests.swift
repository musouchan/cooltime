import XCTest
@testable import CooltimeCore

final class HuggingFaceUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!
    private var period: DailyUsagePeriod { .previousSevenDays(now: now, lagHours: 2) }
    private func row(_ changes: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = ["user": "example", "model": "org/model", "provider": "hf-inference",
            "requestCount": 2, "costCents": 3, "inputTokens": 10, "outputTokens": 20, "cachedInputTokens": 0]
        changes.forEach { result[$0.key] = $0.value }
        return result
    }
    private func data(_ rows: [[String: Any]], day: String = "2026-11-05T00:00:00.000Z") throws -> Data {
        try JSONSerialization.data(withJSONObject: [["period": day, "usage": rows]])
    }
    func testReportedCentsAndRequestsNeverBecomeSharedBalance() throws {
        let snapshot = try HuggingFaceUsage.parse(data([row(), row(["user": NSNull(), "model": NSNull(), "costCents": 7])]),
                                                  linkHeader: nil, period: period, fetchedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.reportedAmount), [10, 4])
        XCTAssertEqual(snapshot.windows[0].reportedUnit, "cents")
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.remainingCount == nil && $0.resetsAt == nil && $0.usedPercent == nil })
        XCTAssertNil(snapshot.credit)
    }
    func testExplicitEmptyDayAndZeroRow() throws {
        XCTAssertEqual(try HuggingFaceUsage.parse(data([]), linkHeader: nil, period: period, fetchedAt: now).windows.first?.reportedAmount, 0)
        XCTAssertEqual(try HuggingFaceUsage.parse(data([row(["costCents": 0])]), linkHeader: nil, period: period, fetchedAt: now).windows.first?.reportedAmount, 0)
    }
    func testRejectsInvalidAmountsAndDuplicateGrains() throws {
        let changes: [[String: Any]] = [["costCents": -1], ["costCents": "1"], ["costCents": 1e20],
            ["requestCount": -1], ["requestCount": 0.5], ["requestCount": 1e20], ["provider": ""]]
        for change in changes {
            XCTAssertThrowsError(try HuggingFaceUsage.parse(data([row(change)]), linkHeader: nil, period: period, fetchedAt: now))
        }
        XCTAssertThrowsError(try HuggingFaceUsage.parse(data([row(), row()]), linkHeader: nil, period: period, fetchedAt: now))
    }
    func testRejectsUnexpectedPaginationAndEmptyOrBadBody() throws {
        for link in ["<https://huggingface.co/next>; rel=\"next\"", "<https://evil.example>; rel=next"] {
            XCTAssertThrowsError(try HuggingFaceUsage.parse(data([row()]), linkHeader: link, period: period, fetchedAt: now))
        }
        for body in ["{}", "[]", #"{"error":"permission denied"}"#] {
            XCTAssertThrowsError(try HuggingFaceUsage.parse(Data(body.utf8), linkHeader: nil, period: period, fetchedAt: now))
        }
    }
    func testRejectsWrongDayOrDuplicatePeriods() throws {
        for day in ["2026-11-06T00:00:00Z", "2026-10-29T00:00:00Z", "2026-11-05T12:00:00Z", "bad"] {
            XCTAssertThrowsError(try HuggingFaceUsage.parse(data([row()], day: day), linkHeader: nil, period: period, fetchedAt: now))
        }
        let bucket = try JSONSerialization.jsonObject(with: data([row()])) as! [[String: Any]]
        let duplicated = try JSONSerialization.data(withJSONObject: bucket + bucket)
        XCTAssertThrowsError(try HuggingFaceUsage.parse(duplicated, linkHeader: nil, period: period, fetchedAt: now))
    }
    func testConfigurationWindowAndManualCoexistence() throws {
        let config = try HuggingFaceUsage.configuration(from: "test-org|example-token")
        XCTAssertEqual(config.organization, "test-org")
        let url = URLComponents(string: HuggingFaceUsage.url(organization: config.organization, period: period))!
        XCTAssertEqual(url.host, "huggingface.co")
        XCTAssertEqual(url.path, "/api/organizations/test-org/billing/usage/inference")
        XCTAssertEqual(url.queryItems?.first { $0.name == "endDate" }?.value, "2026-11-05T23:59:59.999Z")
        XCTAssertEqual(url.queryItems?.first { $0.name == "limit" }?.value, "31")
        for input in ["../other|key", "org?x=y|key", "org|x\ny", "org|"] {
            XCTAssertThrowsError(try HuggingFaceUsage.configuration(from: input))
        }
        XCTAssertEqual(Catalog.service("sheet-95")?.method, .manual)
        XCTAssertEqual(Catalog.service("huggingface-inference-usage")?.method, .apiKey)
    }
}
