import Foundation
import XCTest
@testable import CooltimeCore

final class WorkspaceGeminiAuditUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
    private let user = "sample+ai@example.com"

    func testSelectedUserAndFullPagesProduceAnAuditCount() async throws {
        let period = WorkspaceGeminiAuditUsage.period(now: now)
        XCTAssertEqual(period.firstDay, "2026-10-30")
        XCTAssertEqual(period.lastDay, "2026-11-05")
        let first = event("11")
        var pages = [
            page([first], next: "page+/="),
            page([first, event("12"), event("13", time: "2026-11-06T00:00:00Z")])
        ]
        let snapshot = try await WorkspaceGeminiAuditUsage.fetch(email: user, period: period, fetchedAt: now) { url in
            let components = try XCTUnwrap(URLComponents(string: url))
            XCTAssertEqual(components.host, "admin.googleapis.com")
            XCTAssertEqual(components.path, "/admin/reports/v1/activity/users/\(self.user)/applications/gemini_in_workspace_apps")
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["eventName"], "feature_utilization")
            XCTAssertEqual(query["startTime"], "2026-10-30T00:00:00Z")
            XCTAssertEqual(query["endTime"], "2026-11-06T00:00:00Z")
            XCTAssertEqual(query["pageToken"], pages.count == 2 ? nil : "page+/=")
            XCTAssertFalse(query["fields"]?.contains("parameters") ?? true)
            return pages.removeFirst()
        }
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 2)
        XCTAssertNil(snapshot.windows.first?.remainingCount)
        XCTAssertNil(snapshot.windows.first?.resetsAt)
    }

    func testEmptyOfficialResponseIsZero() async throws {
        let snapshot = try await WorkspaceGeminiAuditUsage.fetch(email: user,
            period: WorkspaceGeminiAuditUsage.period(now: now), fetchedAt: now) { _ in
            Data(#"{"kind":"reports#activities","etag":"x"}"#.utf8)
        }
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 0)
    }

    func testMalformedOutOfScopeAndRepeatedPagesFail() async throws {
        let period = WorkspaceGeminiAuditUsage.period(now: now)
        for payload in [Data("{}".utf8), page([event("10", email: "other@example.com")]),
                        page([event("10", time: "2026-11-07T00:00:00Z")]),
                        page([], next: "loop")] {
            do {
                _ = try await WorkspaceGeminiAuditUsage.fetch(email: user, period: period, fetchedAt: now) { _ in payload }
                XCTFail("Expected invalid report to fail")
            } catch is ParseError {}
        }
    }

    func testFailedLaterPageDoesNotReturnPartialUsage() async throws {
        enum Transport: Error { case unavailable }
        let period = WorkspaceGeminiAuditUsage.period(now: now)
        do {
            _ = try await WorkspaceGeminiAuditUsage.fetch(email: user, period: period, fetchedAt: now) { url in
                if url.contains("pageToken=") { throw Transport.unavailable }
                return self.page([self.event("10")], next: "more")
            }
            XCTFail("Expected second-page failure")
        } catch Transport.unavailable {}
    }

    func testInvalidUserCannotRequestTheDomainAndManualEntryIsPreserved() {
        for bad in ["all", "x/y@example.com", "x@example.com|secret", "x@example.com?test"] {
            XCTAssertThrowsError(try WorkspaceGeminiAuditUsage.email(from: bad))
        }
        XCTAssertEqual(Catalog.service("sheet-119")?.method, .manual)
        XCTAssertEqual(Catalog.service("workspace-gemini-audit-usage")?.method, .apiKey)
    }

    private func event(_ qualifier: String, time: String = "2026-11-01T08:00:00.128Z", email: String? = nil) -> String {
        """
        {"id":{"time":"\(time)","uniqueQualifier":"\(qualifier)","applicationName":"gemini_in_workspace_apps"},
        "actor":{"email":"\(email ?? user)"},"events":[{"type":"ai_usage_event","name":"feature_utilization"}]}
        """
    }

    private func page(_ items: [String], next: String? = nil) -> Data {
        let token = next.map { ",\"nextPageToken\":\"\($0)\"" } ?? ""
        return Data("{\"kind\":\"reports#activities\",\"items\":[\(items.joined(separator: ","))]\(token)}".utf8)
    }
}
