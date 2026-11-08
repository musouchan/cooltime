import XCTest
@testable import CooltimeCore

final class SalesforceDigitalWalletUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let card = #"{"cardDefinitionDeveloperName":"AgentforceCredits","businessEnvType":"Production","usageModel":"Prepaid","unitsConsumed":40,"totalEntitlement":100}"#

    func testSelectsExactCardAndComputesRemaining() throws {
        let json = #"[{"actionName":"computeConsumption","isSuccess":true,"outputValues":{"cards":[{"cardDefinitionDeveloperName":"Other","businessEnvType":"Production","usageModel":"Prepaid","unitsConsumed":99,"totalEntitlement":100},"# + card + #"]}}]"#
        let window = try SalesforceDigitalWalletUsage.parse(Data(json.utf8),
            cardName: "AgentforceCredits", fetchedAt: now).windows.first
        XCTAssertEqual(window?.usedPercent, 40)
        XCTAssertEqual(window?.remainingCount, 60)
        XCTAssertNil(window?.resetsAt)
    }

    func testCapsOverageAtZeroWithoutInventingReset() throws {
        let json = #"[{"actionName":"computeConsumption","isSuccess":true,"outputValues":{"cards":[{"cardDefinitionDeveloperName":"AgentforceCredits","businessEnvType":"Production","usageModel":"Prepaid","unitsConsumed":120,"totalEntitlement":100}]}}]"#
        let window = try SalesforceDigitalWalletUsage.parse(Data(json.utf8),
            cardName: "AgentforceCredits", fetchedAt: now).windows.first
        XCTAssertEqual(window?.remainingCount, 0)
        XCTAssertEqual(window?.reportedAmount, 120)
    }

    func testRejectsFailedMissingAndDuplicateCards() {
        let cases = [
            #"[{"actionName":"computeConsumption","isSuccess":false,"outputValues":{"cards":["# + card + #"]}}]"#,
            #"[{"actionName":"computeConsumption","isSuccess":true,"outputValues":{"cards":[]}}]"#,
            #"[{"actionName":"computeConsumption","isSuccess":true,"outputValues":{"cards":["# + card + "," + card + #"]}}]"#
        ]
        for json in cases {
            XCTAssertThrowsError(try SalesforceDigitalWalletUsage.parse(Data(json.utf8),
                cardName: "AgentforceCredits", fetchedAt: now))
        }
    }

    func testConfigurationRejectsAliasAndCardInjection() throws {
        XCTAssertNoThrow(try SalesforceDigitalWalletUsage.configuration(from: "my-org|AgentforceCredits"))
        for value in ["", "my-org", "my-org;bad|AgentforceCredits", "my-org|../other",
                      "my-org|AgentforceCredits\nInjected"] {
            XCTAssertThrowsError(try SalesforceDigitalWalletUsage.configuration(from: value))
        }
    }

    func testKeepsManualEntry() {
        XCTAssertEqual(Catalog.service("salesforce-wallet-usage")?.method, .apiKey)
        XCTAssertTrue(ManualCatalog.all.contains { $0.id == "sheet-125" })
    }
}
