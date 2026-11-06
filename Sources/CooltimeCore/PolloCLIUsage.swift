import Foundation

public enum PolloCLIUsage {
    private struct AccountStatus: Decodable {
        let availableCredits: Double
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard let status = try? JSONDecoder().decode(AccountStatus.self, from: data),
              (0...9_007_199_254_740_991).contains(status.availableCredits) else {
            throw ParseError.unsupported("Pollo CLIの残高データを読み取れません")
        }
        let credit = CreditBalance(amount: status.availableCredits, currency: "credits",
                                   note: "CLIの選択中プロフィール")
        return Snapshot(credit: credit, fetchedAt: fetchedAt)
    }
}
