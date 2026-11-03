import Foundation

/// 取得先のアカウントを見分けるための情報。メールアドレス・プラン・組織名だけを読む。
/// トークンやパスワードは読まない。
public struct AccountIdentity: Equatable, Sendable {
    public var email: String?
    public var plan: String?
    public var type: AccountType?

    public init(email: String? = nil, plan: String? = nil, type: AccountType? = nil) {
        self.email = email
        self.plan = plan
        self.type = type
    }

    /// 管理画面・一覧に出すアカウント名。
    public var displayName: String? { email ?? plan }
}

public enum ClaudeAccount {
    /// Claude Code が手元に持つ ~/.claude.json の `oauthAccount`。
    /// 使うのは、メールアドレスと、プランが分かる項目（organizationType など）だけ。トークンは読まない。
    public static func parse(_ data: Data) -> AccountIdentity? {
        guard let root = try? json(data),
              let acct = root["oauthAccount"] as? [String: Any],
              let email = acct["emailAddress"] as? String, !email.isEmpty else { return nil }
        return AccountIdentity(email: email, plan: plan(acct))
    }

    /// 例: organizationType が "claude_pro" なら "Pro"。Max は、レート制限の段階名に 5x / 20x が入っているときだけ。
    /// 分からなければ nil（作らない）。
    static func plan(_ acct: [String: Any]) -> String? {
        let type = (acct["organizationType"] as? String)?.lowercased() ?? ""
        let tier = ["organizationRateLimitTier", "userRateLimitTier", "seatTier"]
            .compactMap { acct[$0] as? String }.joined(separator: " ").lowercased()
        if type.contains("max") || tier.contains("max") {
            if tier.contains("20x") { return "Max 20x" }
            if tier.contains("5x") { return "Max 5x" }
            return nil
        }
        if type.contains("pro") { return "Pro" }
        return nil
    }
}

public enum CodexAccount {
    /// `account/read` の応答（JSON-RPC の1行）。項目名は実機で要確認。
    public static func parse(_ data: Data) -> AccountIdentity? {
        guard let root = try? json(data),
              let result = root["result"] as? [String: Any],
              let acct = result["account"] as? [String: Any] else { return nil }
        let email = acct["email"] as? String
        let plan = acct["planType"] as? String
        if email == nil && plan == nil { return nil }
        let business: Set<String> = ["team", "business", "enterprise", "edu"]
        let type: AccountType? = plan.map { business.contains($0.lowercased()) ? .business : .personal }
        return AccountIdentity(email: email, plan: plan.map { $0.capitalized }, type: type)
    }
}
