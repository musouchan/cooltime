import Foundation

public enum FalBilling {
    private struct Account: Decodable {
        struct Credits: Decodable {
            let current_balance: Double
            let currency: String
        }
        let credits: Credits
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard let response = try? JSONDecoder().decode(Account.self, from: data),
              (0...9_007_199_254_740_991).contains(response.credits.current_balance),
              response.credits.currency.utf8.count == 3,
              response.credits.currency.utf8.allSatisfy({ (65...90).contains($0) }) else {
            throw ParseError.unsupported("fal.aiの残高または通貨を読み取れません")
        }
        let credit = CreditBalance(amount: response.credits.current_balance, currency: response.credits.currency)
        return Snapshot(credit: credit, fetchedAt: fetchedAt)
    }
}
