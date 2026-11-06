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
        ServiceDef(id: "sheet-168", name: "HeadshotPro", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://www.headshotpro.com/api",
                   bundleIDs: [], hint: "公式Organization APIからヘッドショット生成用組織クレジット残高を取得。",
                   apiKeyHelp: "HeadshotPro Organization API key"),
        ServiceDef(id: "sheet-20", name: "Devin", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://app.devin.ai/",
                   bundleIDs: [], hint: "Enterprise契約のみ。公式Consumption APIとBudgets APIから現在のEnterprise予算に対するACU残量を取得。利用上限未設定の契約は数値表示しません。",
                   apiKeyHelp: "Enterprise service user token（cog_）。ViewAccountConsumption と ManageAcuLimits 権限が必要"),
        ServiceDef(id: "sheet-86", name: "OpenAI Platform API", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://platform.openai.com/settings/organization/limits",
                   bundleIDs: [], hint: "Admin APIのUsage Read権限で、組織の月間ハード支出上限と当月実コストを取得。強制上限がない場合は残額を表示しません。",
                   apiKeyHelp: "Usage Read権限を持つOpenAI Admin API key"),
        ServiceDef(id: "sheet-87", name: "Anthropic Console API", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://platform.claude.com/usage",
                   bundleIDs: [], hint: "Claude Console組織の公式Usage and Cost Analytics APIから、当月の組織コスト実績を取得。クォータ残量は取得しません。集計遅延あり。",
                   apiKeyHelp: "Claude Console Organization Admin API key（組織管理者権限）"),
        ServiceDef(id: "sheet-90", name: "xAI API", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://console.x.ai/",
                   bundleIDs: [], hint: "xAI Management APIから、チームの当月APIコスト実績を取得。利用枠の残量やGrok Web契約は対象外。",
                   apiKeyHelp: "xAI Management API key（team scope、Billing usage読み取り権限）"),
        ServiceDef(id: "sheet-93", name: "Together AI", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://api.together.ai/settings/billing",
                   bundleIDs: [], hint: "公式Billing Usage APIから、組織の当月USDコスト実績を取得。クレジット残額は取得しません。集計は最大約1時間遅れます。",
                   apiKeyHelp: "Together AI API key（組織全体のBilling Usage read。キー自体はAPI利用にも使用可能）"),
        ServiceDef(id: "sheet-104", name: "Exa", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://dashboard.exa.ai/billing",
                   bundleIDs: [], hint: "Team Management APIからチームのUSDクレジット残高を取得。API機能はチーム単位で有効化が必要。",
                   apiKeyHelp: "Exa Team Management API service key（利用前にsupport@exa.aiへAPI有効化を依頼）"),
        ServiceDef(id: "sheet-112", name: "Context7", kind: .subscription, method: .apiKey,
                   defaultPaymentURL: "https://context7.com/dashboard",
                   bundleIDs: [], hint: "公式Usage APIから本人の月間リクエスト実績・Teamspace追加料金・設定済みの追加料金上限を取得。",
                   apiKeyHelp: "Context7 API key（ctx7sk...、Read権限）"),
        ServiceDef(id: "sheet-113", name: "Make", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://www.make.com/en/billing",
                   bundleIDs: [], hint: "公式Organization Usage APIから、選択した組織の直近30日間のcenticredits消費実績を取得。請求残量ではありません。",
                   apiKeyHelp: "Make token（organizations:read）を region|organizationId|token 形式で入力。region: eu1/eu2/us1/us2"),
        ServiceDef(id: "sheet-81", name: "Elicit", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://elicit.com/developer",
                   bundleIDs: [], hint: "公式Usage APIから請求期間の利用率と、設定済みなら追加利用USD残額を取得。",
                   apiKeyHelp: "Elicit API key（利用資格・API access opt-inが必要）"),
        ServiceDef(id: "sheet-71", name: "Poe", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://poe.com/api/keys",
                   bundleIDs: [], hint: "公式Usage APIからアカウントの利用可能ポイントを取得。",
                   apiKeyHelp: "Poe API key"),
        ServiceDef(id: "sheet-121", name: "Apollo AI", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://app.apollo.io/#/settings/billing",
                   bundleIDs: [], hint: "公式Usage APIからチームのcredit type別使用量・残数・サイクル終了を取得。",
                   apiKeyHelp: "credit_usage_stats_read権限のAPIキー、またはMaster API key"),
        ServiceDef(id: "sheet-29", name: "v0", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://v0.app/",
                   bundleIDs: [], hint: "公式 Platform APIから残クレジットと請求サイクル終了を取得。",
                   apiKeyHelp: "v0 Platform API キー"),
        ServiceDef(id: "browserbase-usage", name: "Browserbase（プロジェクト利用実績）", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://www.browserbase.com/overview",
                   bundleIDs: [], hint: "選択した1プロジェクトのブラウザー利用分数とプロキシ転送量を取得。集計期間はAPIに記載されません。",
                   apiKeyHelp: "プロジェクトID|APIキー の形式で入力"),
        ServiceDef(id: "langsmith-trace-usage", name: "LangSmith（トレース実績）", kind: .credit, method: .apiKey,
                   defaultPaymentURL: "https://smith.langchain.com/settings",
                   bundleIDs: [], hint: "選択した1ワークスペースの直近7 UTC日（当日除く）の請求対象トレース数。",
                   apiKeyHelp: "region|ワークスペースUUID|APIキー（region: us/eu、organization:read）"),
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
