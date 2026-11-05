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
    /// 利用者が確認済みの数値を記録し、CSVで取り込む（自動通信なし）。
    case manual
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
    public static let all: [ServiceDef] = automatic + ManualCatalog.all
    public static let automatic: [ServiceDef] = [
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
        ServiceDef(id: "sheet-11", name: "Google Antigravity", kind: .credit, method: .statuslineFile,
                   defaultPaymentURL: "https://antigravity.google/",
                   bundleIDs: [], hint: "Antigravity CLIのstatusLine JSONからモデル別quotaをローカル取得。会話や認証情報は保存しません。",
                   apiKeyHelp: nil),
        ServiceDef(id: "sheet-103", name: "Tavily", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://app.tavily.com/",
                   bundleIDs: [], hint: "公式 Usage API からキー・アカウントの利用量と上限を取得。",
                   apiKeyHelp: "Tavily API キー"),
        ServiceDef(id: "sheet-29", name: "v0", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://v0.app/",
                   bundleIDs: [], hint: "公式 Platform APIから残クレジットと請求サイクル終了を取得。",
                   apiKeyHelp: "v0 Platform API キー"),
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
        // ここから下は、調査表（スプレッドシート）の順。実機で要確認。
        ServiceDef(id: "runway", name: "Runway API", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://dev.runwayml.com/",
                   bundleIDs: [], hint: "APIクレジット残高。Web の枠とは別です。", apiKeyHelp: "Runway API キー"),
        ServiceDef(id: "luma", name: "Luma Dream Machine API", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://lumalabs.ai/api",
                   bundleIDs: [], hint: "APIクレジット残高。Web の枠とは別です。", apiKeyHelp: "Luma API キー"),
        ServiceDef(id: "stability", name: "Stability AI", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://platform.stability.ai/account/credits",
                   bundleIDs: [], hint: "APIクレジット残高。購入分は、自動では戻りません。", apiKeyHelp: "Stability API キー"),
        ServiceDef(id: "apify", name: "Apify", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://console.apify.com/billing",
                   bundleIDs: [], hint: "月の利用額と、期間の終わり。", apiKeyHelp: "Apify API トークン"),
        ServiceDef(id: "serpapi", name: "SerpAPI", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://serpapi.com/dashboard",
                   bundleIDs: [], hint: "月の検索回数と、更新日。", apiKeyHelp: "SerpAPI キー"),
        ServiceDef(id: "deepl", name: "DeepL API", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://www.deepl.com/your-account/subscription",
                   bundleIDs: [], hint: "月の翻訳文字数。Web の契約とは別です。", apiKeyHelp: "DeepL API キー（無料版は :fx で終わる）"),
        ServiceDef(id: "photoroom", name: "Photoroom API", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://app.photoroom.com/api-dashboard",
                   bundleIDs: [], hint: "画像処理のクレジット残高。", apiKeyHelp: "Photoroom API キー"),
        ServiceDef(id: "meshy", name: "Meshy", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://www.meshy.ai/api",
                   bundleIDs: [], hint: "3D 生成のクレジット残高。", apiKeyHelp: "Meshy API キー"),
        // 公式の資料で確認できたもの。
        ServiceDef(id: "copilot", name: "GitHub Copilot", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://github.com/settings/billing",
                   bundleIDs: [], hint: "個人契約の月のAIクレジット。プランを選ぶと残りが出ます。会社・組織の契約は対象外。",
                   apiKeyHelp: "細かい権限のトークン（ユーザーの「Plan」読み取り）"),
        ServiceDef(id: "synthesia", name: "Synthesia API", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://app.synthesia.io/",
                   bundleIDs: [], hint: "期間のクレジットの残りと、期間の終わり。", apiKeyHelp: "Synthesia API キー"),
        ServiceDef(id: "tripo", name: "Tripo AI", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://platform.tripo3d.ai/",
                   bundleIDs: [], hint: "3D 生成のクレジット残高。", apiKeyHelp: "Tripo API キー"),
    ]

    public static func service(_ id: String) -> ServiceDef? { all.first { $0.id == id } }
}
