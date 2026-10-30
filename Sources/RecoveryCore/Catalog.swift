import Foundation

public enum SourceKind: String, Codable, Sendable {
    case claudeStatusline   // Claude Code のステータスライン（公式）
    case codexAppServer     // Codex の app-server（公式）
    case apiKey             // 各社の公式API + APIキー
}

/// 追加できるサービスの候補。ここに無いものは「取得できない」ので載せない。
public struct CatalogEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let symbol: String          // SF Symbols 名（ロゴは同梱しない）
    public let kind: SourceKind
    public let provider: BalanceProvider?
    public let isCreditOnly: Bool      // 時間では戻らない（クレジット）
    public let note: String
    /// 支払いページの標準URL。画面から変更できる。実装時に各社のページで確認すること。
    public let defaultPaymentURL: String?
    /// 取得方法の格。非公式なもの（Cookie・内部API など）は .experimental にして、既定ではオフにする。
    /// いまの候補はすべて公式。
    public var tier: AcquisitionTier = .official

    public var needsAPIKey: Bool { kind == .apiKey }
}

public enum Catalog {
    public static let all: [CatalogEntry] = [
        .init(id: "anthropic", name: "Anthropic（Claude・Claude Code）", symbol: "sparkles",
              kind: .claudeStatusline, provider: nil, isCreditOnly: false,
              note: "Claude Code のステータスラインから。Pro／Max 契約のみ。",
              defaultPaymentURL: "https://platform.claude.com/settings/billing"),
        .init(id: "openai-codex", name: "OpenAI（Work・Codex）", symbol: "terminal",
              kind: .codexAppServer, provider: nil, isCreditOnly: false,
              note: "codex コマンドの app-server から。ログイン済みであること。",
              defaultPaymentURL: nil),
        .init(id: "elevenlabs", name: "ElevenLabs", symbol: "waveform",
              kind: .apiKey, provider: .elevenLabs, isCreditOnly: false,
              note: "月の文字数と次のリセット日時。", defaultPaymentURL: nil),
        .init(id: "firecrawl", name: "Firecrawl", symbol: "flame",
              kind: .apiKey, provider: .firecrawl, isCreditOnly: false,
              note: "月のクレジットと請求期間の終了日。", defaultPaymentURL: nil),
        .init(id: "vercel-ai-gateway", name: "Vercel AI Gateway", symbol: "triangle",
              kind: .apiKey, provider: .vercelAIGateway, isCreditOnly: true,
              note: "クレジット残高。チャージで戻る。", defaultPaymentURL: "https://vercel.com/dashboard"),
        .init(id: "openrouter", name: "OpenRouter", symbol: "arrow.triangle.branch",
              kind: .apiKey, provider: .openRouter, isCreditOnly: true,
              note: "残額。", defaultPaymentURL: "https://openrouter.ai/settings/credits"),
        .init(id: "deepseek", name: "DeepSeek", symbol: "fish",
              kind: .apiKey, provider: .deepSeek, isCreditOnly: true,
              note: "残高。", defaultPaymentURL: "https://platform.deepseek.com/top_up")
    ]

    public static func entry(_ id: String) -> CatalogEntry? { all.first { $0.id == id } }
}

/// 利用者が追加したサービス。APIキーはここに入れず Keychain に置く。
public struct ServiceConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: String                 // UUID。Keychain の項目名にも使う
    public var catalogID: String
    public var account: String            // 例: 個人 / RETHIC
    public var kind: AccountKind
    public var plan: String
    public var paymentURL: String
    public var browserBundleID: String?   // 支払いページを開くブラウザ

    public init(catalogID: String, account: String = "", kind: AccountKind = .personal,
                plan: String = "", paymentURL: String = "", browserBundleID: String? = nil) {
        self.id = UUID().uuidString
        self.catalogID = catalogID
        self.account = account
        self.kind = kind
        self.plan = plan
        self.paymentURL = paymentURL
        self.browserBundleID = browserBundleID
    }
}
