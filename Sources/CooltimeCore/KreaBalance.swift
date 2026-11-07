import Foundation

public enum KreaBalance {
    private struct ToolResult: Decodable {
        struct Content: Decodable { let type: String; let text: String? }
        let isError: Bool?
        let content: [Content]?
        let structuredContent: Balance?
    }

    private struct Balance: Decodable {
        struct ComputeUnits: Decodable { let total: Double }
        let compute_units: ComputeUnits
    }

    public static func profile(from value: String) throws -> String {
        let profile = value.trimmingCharacters(in: .whitespaces)
        guard profile.range(of: #"\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\z"#, options: .regularExpression) != nil else {
            throw ParseError.unsupported("Krea CLIのプロファイル名を入力してください（例: default）")
        }
        return profile
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let decoder = JSONDecoder()
        guard data.count <= 65_536, let result = try? decoder.decode(ToolResult.self, from: data),
              result.isError != true else { throw invalid() }
        let balance: Balance
        if let structured = result.structuredContent {
            balance = structured
        } else {
            guard let content = result.content, content.count == 1, content[0].type == "text",
                  let text = content[0].text,
                  let parsed = try? decoder.decode(Balance.self, from: Data(text.utf8)) else { throw invalid() }
            balance = parsed
        }
        let amount = balance.compute_units.total
        guard amount.isFinite, (0...9_007_199_254_740_991).contains(amount) else { throw invalid() }
        return Snapshot(credit: CreditBalance(amount: amount, currency: "compute units"), fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("KreaのワークスペースCompute Units残高を確認できません")
    }
}
