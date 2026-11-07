import XCTest
@testable import CooltimeCore

final class JetBrainsAIQuotaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func xml(quota: String, refill: String? = nil) -> Data {
        func escaped(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;")
                 .replacingOccurrences(of: "\"", with: "&quot;")
                 .replacingOccurrences(of: "<", with: "&lt;")
        }
        let refillOption = refill.map { #"<option name="nextRefill" value="\#(escaped($0))"/>"# } ?? ""
        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <application><component name="AIAssistantQuotaManager2">
        <option name="quotaInfo" value="\(escaped(quota))"/>\(refillOption)
        </component></application>
        """.utf8)
    }

    func testParsesTariffQuotaAndKnownRefill() throws {
        let quota = #"{"type":"Available","current":"25","maximum":"100","available":"75","tariffQuota":{"current":"25","maximum":"100","available":"75"},"topUpQuota":{"current":"10","maximum":"20","available":"10"}}"#
        let refill = #"{"type":"Known","next":"2027-01-15T00:00:00Z","tariff":{"duration":"PT720H"}}"#
        let snapshot = try JetBrainsAIQuota.parse(xml(quota: quota, refill: refill), fetchedAt: now)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 25)
        XCTAssertEqual(snapshot.windows.first?.reportedAmount, 25)
        XCTAssertNotNil(snapshot.windows.first?.resetsAt)
        XCTAssertNil(snapshot.windows.first?.remainingCount)
    }

    func testUsesOnlyTariffNotTopUpOrCombinedQuota() throws {
        let quota = #"{"type":"Available","current":"40","maximum":"150","available":"110","tariffQuota":{"current":30,"maximum":100,"available":70},"topUpQuota":{"current":10,"maximum":50,"available":40}}"#
        let window = try JetBrainsAIQuota.parse(xml(quota: quota), fetchedAt: now).windows.first
        XCTAssertEqual(window?.usedPercent, 30)
        XCTAssertEqual(window?.reportedAmount, 30)
        XCTAssertNil(window?.resetsAt)
    }

    func testRejectsMissingComponentInconsistentAndMalformedValues() {
        let missing = Data("<application/>".utf8)
        let inconsistent = #"{"type":"Available","tariffQuota":{"current":25,"maximum":100,"available":90}}"#
        let negative = #"{"type":"Available","tariffQuota":{"current":-1,"maximum":100,"available":101}}"#
        XCTAssertThrowsError(try JetBrainsAIQuota.parse(missing, fetchedAt: now))
        XCTAssertThrowsError(try JetBrainsAIQuota.parse(xml(quota: inconsistent), fetchedAt: now))
        XCTAssertThrowsError(try JetBrainsAIQuota.parse(xml(quota: negative), fetchedAt: now))
    }

    func testRejectsUnknownOrInvalidRefillWithoutGuessing() {
        let quota = #"{"type":"Available","tariffQuota":{"current":0,"maximum":100,"available":100}}"#
        let invalid = #"{"type":"Known","next":"not-a-date"}"#
        XCTAssertThrowsError(try JetBrainsAIQuota.parse(xml(quota: quota, refill: invalid), fetchedAt: now))
    }

    func testKeepsManualEntry() {
        XCTAssertEqual(Catalog.service("jetbrains-ai-local-quota")?.method, .statuslineFile)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-15" })
    }
}
