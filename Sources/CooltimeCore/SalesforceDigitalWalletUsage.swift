import Foundation

/// A single official Digital Wallet consumption card selected by its exact developer name.
public enum SalesforceDigitalWalletUsage {
    public struct Configuration: Sendable {
        public let orgAlias: String
        public let cardName: String
    }

    private struct Action: Decodable {
        struct Output: Decodable {
            struct Card: Decodable {
                let cardDefinitionDeveloperName: String
                let businessEnvType: String
                let usageModel: String
                let unitsConsumed: Double
                let totalEntitlement: Double
            }
            let cards: [Card]
        }
        let actionName: String
        let isSuccess: Bool
        let outputValues: Output?
    }

    public static func configuration(from input: String) throws -> Configuration {
        let parts = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, safeAlias(parts[0]), safeCard(parts[1]) else { throw invalid() }
        return Configuration(orgAlias: parts[0], cardName: parts[1])
    }

    public static func parse(_ data: Data, cardName: String, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 2_000_000, safeCard(cardName),
              let actions = try? JSONDecoder().decode([Action].self, from: data),
              actions.count == 1, let action = actions.first,
              action.actionName == "computeConsumption", action.isSuccess,
              let output = action.outputValues, output.cards.count <= 1_000 else { throw invalid() }
        let selected = output.cards.filter { $0.cardDefinitionDeveloperName == cardName }
        guard selected.count == 1, let card = selected.first,
              !card.businessEnvType.isEmpty, card.businessEnvType.utf8.count <= 128,
              !card.usageModel.isEmpty, card.usageModel.utf8.count <= 128,
              valid(card.unitsConsumed), valid(card.totalEntitlement),
              card.totalEntitlement > 0 else { throw invalid() }
        let remaining = max(0, card.totalEntitlement - card.unitsConsumed)
        return Snapshot(windows: [
            UsageWindow(label: "Salesforce Digital Wallet・\(cardName)",
                        usedPercent: card.unitsConsumed / card.totalEntitlement * 100,
                        remainingCount: remaining,
                        reportedAmount: card.unitsConsumed,
                        reportedUnit: "entitlement units")
        ], fetchedAt: fetchedAt)
    }

    private static func safeAlias(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) ||
            [45, 46, 64, 95].contains(byte)
        }
    }

    private static func safeCard(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) ||
            byte == 95
        }
    }

    private static func valid(_ value: Double) -> Bool {
        value.isFinite && (0...9_007_199_254_740_991).contains(value)
    }

    private static func invalid() -> ParseError {
        .unsupported("Salesforce Digital Walletの指定カード利用状況を確認できません")
    }
}
