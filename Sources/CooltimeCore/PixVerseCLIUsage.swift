import Foundation

public enum PixVerseCLIUsage {
    private struct AccountInfo: Decodable {
        struct Credits: Decodable { let total: Int64 }
        struct Workspace: Decodable { let workspaceId: Int64 }
        let credits: Credits
        let workspace: Workspace
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard let account = try? JSONDecoder().decode(AccountInfo.self, from: data),
              account.workspace.workspaceId >= 0,
              (0...9_007_199_254_740_991).contains(account.credits.total) else {
            throw ParseError.unsupported("PixVerse CLIの残高データを読み取れません")
        }
        let scope = account.workspace.workspaceId == 0 ? "個人ワークスペース" : "チームの共有枠"
        let balance = CreditBalance(amount: Double(account.credits.total), currency: "credits", note: scope)
        return Snapshot(credit: balance, fetchedAt: fetchedAt)
    }
}
