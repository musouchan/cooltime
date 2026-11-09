import Foundation

public struct ServiceSection: Identifiable {
    public let category: ServiceCategory
    public let services: [ServiceDef]
    public var id: ServiceCategory { category }
}

/// 追加画面でサービスを探すための分類。取得方法や残量の種類とは独立している。
public enum ServiceCategory: String, CaseIterable, Identifiable, Sendable {
    case chat = "チャット・検索"
    case coding = "コーディング"
    case image = "画像・デザイン"
    case videoAudio = "動画・音声"
    case api = "AI API・開発基盤"
    case work = "業務・自動化"
    case research = "学習・研究"
    case professional = "専門業務"
    case spatial = "3D・ゲーム"
    case other = "その他"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .image: "paintpalette"
        case .videoAudio: "play.rectangle"
        case .api: "server.rack"
        case .work: "briefcase"
        case .research: "books.vertical"
        case .professional: "person.text.rectangle"
        case .spatial: "cube.transparent"
        case .other: "square.grid.2x2"
        }
    }

    public static func category(for service: ServiceDef) -> ServiceCategory {
        switch service.id {
        case "claude", "codex", "sheet-71", "sheet-84", "you-api-balance": return .chat
        case "aider-local-usage", "gemini-cli-local-usage", "sheet-11", "sheet-20", "sheet-29",
             "jetbrains-ai-local-quota", "kiro-enterprise-usage", "augment-credit-usage",
             "opencode-go-usage", "copilot": return .coding
        case "openart-cli-balance", "magnific-team-credits", "figma-ai-usage", "photoroom",
             "stability", "sheet-168": return .image
        case "kling-api-package-usage", "scenario-cu-usage", "runway", "luma", "synthesia",
             "elevenlabs": return .videoAudio
        case "meshy", "tripo": return .spatial
        case "ada-resolution-usage", "intercom-fin-conversations", "grammarly-ai-usage",
             "jasper-api-usage", "salesforce-wallet-usage", "zendesk-ai-export-usage",
             "microsoft365-copilot-report", "workspace-gemini-audit", "datadog-bits-usage",
             "thoughtspot-spotter-usage", "sheet-121", "deepl": return .work
        case "sheet-81": return .research
        case "livekit-cloud-sessions", "browserbase-usage", "langsmith-trace-usage",
             "aws-bedrock-usage", "azure-foundry-monitor-usage", "composio-project-usage",
             "mistral-admin-spend-status", "gemini-api-request-usage", "vertex-token-monitoring",
             "fal-api-balance", "huggingface-inference-usage", "sheet-86", "sheet-87", "sheet-90",
             "sheet-93", "sheet-103", "sheet-104", "sheet-112",
             "firecrawl", "vercel-ai-gateway", "openrouter", "deepseek",
             "apify", "serpapi": return .api
        case "sheet-113": return .work
        default: break
        }

        guard service.id.hasPrefix("sheet-"), let row = Int(service.id.dropFirst(6)) else { return .other }
        switch row {
        case 12...35: return .coding
        case 36...46, 165...171: return .image
        case 47...66: return .videoAudio
        case 67...73, 84...85, 185...187: return .chat
        case 74...80, 113...115, 118...139, 176...183: return .work
        case 81...83, 140...147: return .research
        case 86...112, 116...117: return .api
        case 148...159, 184: return .professional
        case 160...164, 174...175: return .spatial
        default: return .other
        }
    }

    /// カタログの元の並びを保ち、検索時にもカテゴリの見出しを残す。
    public static func sections(
        from services: [ServiceDef], search: String = "", selected: ServiceCategory? = nil
    ) -> [ServiceSection] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = services.filter { service in
            (selected == nil || category(for: service) == selected)
                && (query.isEmpty || service.name.localizedStandardContains(query))
        }
        return allCases.compactMap { category in
            let members = matches.filter { self.category(for: $0) == category }
            return members.isEmpty ? nil : ServiceSection(category: category, services: members)
        }
    }
}
