import XCTest
@testable import CooltimeCore

final class WorkspaceGeminiUsageTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
    private let configuration = "reports-project|user+team@example.com"

    func testFetchesOnlyTheSelectedUserAndDeduplicatesPages() async throws {
        let config = try WorkspaceGeminiUsage.configuration(from: configuration)
        let period = WorkspaceGeminiUsage.period(now: now)
        let activity = #"{"id":{"time":"2026-11-01T12:00:00.123Z","uniqueQualifier":"123"},"events":[{"name":"feature_utilization"}]}"#
        let boundary = #"{"id":{"time":"2026-11-06T00:00:00Z","uniqueQualifier":"456"},"events":[{"name":"feature_utilization"}]}"#
        var urls = [String]()
        let snapshot = try await WorkspaceGeminiUsage.fetch(config: config, period: period, fetchedAt: now) { url in
            urls.append(url)
            if urls.count == 1 {
                return Data("{\"kind\":\"admin#reports#activities\",\"items\":[\(activity)],\"nextPageToken\":\"a+b\"}".utf8)
            }
            return Data("{\"kind\":\"admin#reports#activities\",\"items\":[\(activity),\(boundary)]}".utf8)
        }
        let first = try XCTUnwrap(URLComponents(string: urls[0]))
        XCTAssertEqual(config.projectID, "reports-project")
        XCTAssertEqual(first.host, "admin.googleapis.com")
        XCTAssertEqual(first.path, "/admin/reports/v1/activity/users/user+team@example.com/applications/gemini_in_workspace_apps")
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(first.queryItems).map { ($0.name, $0.value) })
        XCTAssertEqual(query["eventName"], "feature_utilization")
        XCTAssertEqual(query["startTime"], "2026-10-30T00:00:00Z")
        XCTAssertEqual(query["endTime"], "2026-11-06T00:00:00Z")
        XCTAssertEqual(query["fields"], "kind,nextPageToken,items(id(time,uniqueQualifier),events(name))")
        XCTAssertTrue(urls[1].contains("pageToken=a%2Bb"))
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 1)
        XCTAssertNil(snapshot.windows.first?.remainingCount)
        XCTAssertNil(snapshot.windows.first?.resetsAt)
        XCTAssertNil(snapshot.credit)
    }

    func testEmptyAuditReportIsZero() async throws {
        let snapshot = try await WorkspaceGeminiUsage.fetch(config: .init(projectID: "reports-project", email: "user@example.com"),
            period: WorkspaceGeminiUsage.period(now: now), fetchedAt: now) { _ in
            Data(#"{"kind":"admin#reports#activities"}"#.utf8)
        }
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 0)
    }

    func testMalformedPageAndRepeatedPageTokenFail() async throws {
        let config = try WorkspaceGeminiUsage.configuration(from: configuration)
        for page in [#"{}"#, #"{"kind":"admin#reports#activities","nextPageToken":"repeat"}"#] {
            do {
                _ = try await WorkspaceGeminiUsage.fetch(config: config, period: WorkspaceGeminiUsage.period(now: now),
                                                         fetchedAt: now) { _ in Data(page.utf8) }
                XCTFail("Invalid pagination produced a snapshot")
            } catch is ParseError { }
        }
    }

    func testInvalidConfigurationAndManualEntry() {
        for input in ["reports-project|all", "../reports|user@example.com", "reports-project|user/other@example.com"] {
            XCTAssertThrowsError(try WorkspaceGeminiUsage.configuration(from: input))
        }
        XCTAssertEqual(Catalog.service("sheet-119")?.method, .manual)
        XCTAssertEqual(Catalog.service("workspace-gemini-audit")?.method, .apiKey)
    }
}
