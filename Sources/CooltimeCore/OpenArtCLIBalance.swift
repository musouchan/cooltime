import Foundation
import CoreFoundation

/// Accepts only an explicit numeric balance from the official CLI account JSON.
public enum OpenArtCLIBalance {
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 131_072,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["credits"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { throw invalid() }
        let balance = number.doubleValue
        guard balance.isFinite, balance >= 0, balance <= 9_007_199_254_740_991 else { throw invalid() }
        return Snapshot(credit: CreditBalance(amount: balance, currency: "credits",
                                              note: "OpenArt CLIの選択中ワークスペース"), fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("OpenArt公式CLIの残クレジットを確認できません（account --json の形式を確認してください）")
    }
}
