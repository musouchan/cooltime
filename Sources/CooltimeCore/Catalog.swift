import Foundation

public enum ServiceKind: Sendable {
    /// 時間で戻る枠（5時間・週・月）。
    case subscription
    /// 残高。時間では戻らない。
    case credit
}

public enum FetchMethod: Sendable {
    /// Claude Code のステータスラインが書き出すファイルを読む（通信なし・自動で読み直す）。
    case statuslineFile
    /// `codex app-server` に問い合わせる（更新ボタンのときだけ）。
    case codexAppServer
    /// 公式 API をAPIキーで呼ぶ（更新ボタンのときだけ）。
    case apiKey
}

public struct ServiceDef: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: ServiceKind
    public let method: FetchMethod
    public let defaultPaymentURL: String
    /// インストール済みアプリのアイコンを借りるための Bundle ID。
    public let bundleIDs: [String]
    public let hint: String
    public let apiKeyHelp: String?
}

public enum Catalog {
    public static let all: [ServiceDef] = [
        ServiceDef(id: "claude", name: "Claude / Claude Code", kind: .subscription, method: .statuslineFile,
                   defaultPaymentURL: "https://claude.ai/settings/billing",
                   bundleIDs: ["com.anthropic.claudefordesktop"],
                   hint: "Pro / Max 契約のみ。公式の Claude Code（/usage）から、1分おきに自動で取得します。",
                   apiKeyHelp: nil),
        ServiceDef(id: "codex", name: "ChatGPT / Codex", kind: .subscription, method: .codexAppServer,
                   defaultPaymentURL: "https://chatgpt.com/",
                   bundleIDs: ["com.openai.chat", "com.openai.codex"],
                   hint: "ChatGPT アプリか Codex CLI にログイン済みであること。1分おきに自動で取得します。",
                   apiKeyHelp: nil),
        ServiceDef(id: "elevenlabs", name: "ElevenLabs", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://elevenlabs.io/app/subscription",
                   bundleIDs: [], hint: "月の文字数と次のリセット日時。", apiKeyHelp: "APIキー（user_read 権限）"),
        ServiceDef(id: "firecrawl", name: "Firecrawl", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://www.firecrawl.dev/app",
                   bundleIDs: [], hint: "月のクレジットと請求期間の終了日。", apiKeyHelp: "APIキー"),
        ServiceDef(id: "vercel-ai-gateway", name: "Vercel AI Gateway", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://vercel.com/dashboard",
                   bundleIDs: [], hint: "クレジット残高。", apiKeyHelp: "AI Gateway のAPIキー"),
        ServiceDef(id: "openrouter", name: "OpenRouter", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://openrouter.ai/settings/credits",
                   bundleIDs: [], hint: "上限を設定したキーのみ。残額と、予算のリセット。", apiKeyHelp: "上限を設定したAPIキー"),
        ServiceDef(id: "deepseek", name: "DeepSeek", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://platform.deepseek.com/top_up",
                   bundleIDs: [], hint: "クレジット残高。", apiKeyHelp: "APIキー"),
    ]

    public static func service(_ id: String) -> ServiceDef? { all.first { $0.id == id } }
}
