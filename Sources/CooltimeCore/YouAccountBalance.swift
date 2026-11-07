import Foundation

/// Official You.com API Platform balance, distinct from consumer subscriptions.
public enum YouAccountBalance {
    private struct Envelope: Decodable {
        struct Account: Decodable {
            struct Attributes: Decodable { let balance: Double }
            let type: String
            let id: String
            let attributes: Attributes
        }
        let data: Account
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard let response = try? JSONDecoder().decode(Envelope.self, from: data),
              response.data.type == "account", !response.data.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (0...9_007_199_254_740_991).contains(response.data.attributes.balance) else {
            throw ParseError.unsupported("You.com APIのアカウント残高を読み取れません")
        }
        // Published units are cents and may be fractional. Do not truncate to whole cents.
        return Snapshot(credit: CreditBalance(amount: response.data.attributes.balance / 100,
                                              currency: "USD",
                                              note: "APIキーが属する個人または組織の共有残高"),
                        fetchedAt: fetchedAt)
    }
}
