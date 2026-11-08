import CryptoKit
import XCTest
@testable import CooltimeCore

final class LiveKitCloudSessionsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
    private let fixture = "p_sample|fixture-key|fixture-secret"

    func testSignsShortLivedAnalyticsOnlyToken() throws {
        let config = try LiveKitCloudSessions.configuration(from: fixture)
        let token = try LiveKitCloudSessions.accessToken(config: config, now: now)
        let parts = token.components(separatedBy: ".")
        XCTAssertEqual(parts.count, 3)
        let claims = try XCTUnwrap(JSONSerialization.jsonObject(with: decode(parts[1])) as? [String: Any])
        XCTAssertEqual(claims["iss"] as? String, "fixture-key")
        XCTAssertEqual(claims["video"] as? [String: Bool], ["roomList": true])
        XCTAssertEqual(claims["exp"] as? Int, Int(now.timeIntervalSince1970) + 300)
        XCTAssertNil(claims["sip"])
        let signature = try decode(parts[2])
        XCTAssertTrue(HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: Data("\(parts[0]).\(parts[1])".utf8),
                                                            using: SymmetricKey(data: Data("fixture-secret".utf8))))
    }

    func testReadsAllPagesForOneProjectAndDay() async throws {
        let config = try LiveKitCloudSessions.configuration(from: fixture)
        var urls = [String]()
        let result = try await LiveKitCloudSessions.fetch(config: config, fetchedAt: now) { url in
            urls.append(url)
            return page(ids: urls.count == 1 ? Array(1...100) : [101])
        }
        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls[0].contains("/p_sample/sessions?start=2026-11-06&end=2026-11-06&page=0&limit=100"))
        XCTAssertTrue(urls[1].contains("page=1"))
        XCTAssertEqual(result.windows.first?.reportedAmount, 101)
        XCTAssertNil(result.windows.first?.remainingCount)
        XCTAssertNil(result.credit)
    }

    func testRejectsMalformedDuplicateAndOutOfDayResponses() async throws {
        let config = try LiveKitCloudSessions.configuration(from: fixture)
        for data in [Data("{}".utf8), page(ids: [1, 1]), page(ids: [1], timestamp: "2026-11-07T02:00:00Z")] {
            do {
                _ = try await LiveKitCloudSessions.fetch(config: config, fetchedAt: now) { _ in data }
                XCTFail("Invalid response produced a snapshot")
            } catch is ParseError { }
        }
    }

    func testRejectsUnsafeConfigurationAndKeepsManualEntry() {
        for value in ["../other|key|secret", "p_sample|key|", "p_sample|key|secret\n"] {
            XCTAssertThrowsError(try LiveKitCloudSessions.configuration(from: value))
        }
        XCTAssertEqual(Catalog.service("sheet-135")?.method, .manual)
        XCTAssertEqual(Catalog.service("livekit-cloud-sessions")?.method, .apiKey)
    }

    private func page(ids: [Int], timestamp: String = "2026-11-06T03:00:00.123Z") -> Data {
        let items = ids.map { "{\"sessionId\":\"room-\($0)\",\"createdAt\":\"\(timestamp)\"}" }.joined(separator: ",")
        return Data("{\"sessions\":[\(items)]}".utf8)
    }

    private func decode(_ value: String) throws -> Data {
        let padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.count % 4) % 4)
        return try XCTUnwrap(Data(base64Encoded: padded))
    }
}
