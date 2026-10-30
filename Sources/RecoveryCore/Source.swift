import Foundation

// 取得方法を差し込めるようにするための仕組み。
//
// 新しい取得方法を足すときの手順:
//   1. UsageSource に従う型を作る（例: CookieSessionSource）
//   2. SourceKind に case を足す（例: .cookieSession）
//   3. SourceRegistry.standard に登録する
//   4. Catalog に、そのサービスを tier: .experimental で足す
// 画面や状態の判定は変えなくてよい。登録が無い取得方法は「まだ入っていません」と出るだけ。

/// 取得方法の格。実験的なものは、既定でオフ。利用者が確認画面で明示的にオンにしたときだけ動く。
public enum AcquisitionTier: String, Codable, Sendable {
    case official       // 公式の仕組み（ステータスライン、app-server、公式API）
    case experimental   // 非公式（Cookie・ウェブセッション、内部API など）
}

public protocol SecretStore: Sendable {
    func secret(for configID: String) -> String?
}

#if canImport(Security)
public struct KeychainSecretStore: SecretStore {
    public init() {}
    public func secret(for configID: String) -> String? { Keychain.load(account: configID) }
}
#endif

public struct SourceContext: Sendable {
    public let http: HTTPClient
    public let secrets: SecretStore
    public init(http: HTTPClient, secrets: SecretStore) {
        self.http = http
        self.secrets = secrets
    }
}

public protocol UsageSource: Sendable {
    func fetch(entry: CatalogEntry, config: ServiceConfig, context: SourceContext) async throws -> SourceResult
}

public struct SourceRegistry: Sendable {
    private let sources: [SourceKind: any UsageSource]

    public init(_ sources: [SourceKind: any UsageSource]) { self.sources = sources }

    /// いま入っている取得方法。ここに足せば、画面側は何も変えずに使える。
    public static let standard = SourceRegistry([
        .claudeStatusline: StatuslineAdapter(),
        .codexAppServer: CodexAdapter(),
        .apiKey: APIKeyAdapter()
    ])

    public func source(for kind: SourceKind) -> (any UsageSource)? { sources[kind] }
}

struct StatuslineAdapter: UsageSource {
    func fetch(entry: CatalogEntry, config: ServiceConfig, context: SourceContext) async throws -> SourceResult {
        try StatuslineSource().read()
    }
}

struct CodexAdapter: UsageSource {
    func fetch(entry: CatalogEntry, config: ServiceConfig, context: SourceContext) async throws -> SourceResult {
        try await CodexSource().fetch()
    }
}

struct APIKeyAdapter: UsageSource {
    func fetch(entry: CatalogEntry, config: ServiceConfig, context: SourceContext) async throws -> SourceResult {
        guard let provider = entry.provider, let key = context.secrets.secret(for: config.id) else {
            throw SourceError.notAvailable("APIキーが未設定です")
        }
        return try await provider.fetch(apiKey: key, client: context.http)
    }
}
