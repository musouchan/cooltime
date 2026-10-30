import SwiftUI
import AppKit
import RecoveryCore

struct Row: Identifiable {
    let config: ServiceConfig
    let entry: CatalogEntry
    let snapshot: Snapshot?
    let state: DisplayState
    var id: String { config.id }

    var title: String { entry.name }
    var accountText: String {
        [config.account, config.kind.label].filter { !$0.isEmpty }.joined(separator: " ・ ")
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var configs: [ServiceConfig] { didSet { persist() } }
    @Published private(set) var snapshots: [String: Snapshot] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var refreshing: Set<String> = []
    @Published private(set) var now: Date

    /// 実験的（非公式）な取得を使うか。既定はオフ。確認画面で明示的にオンにしたときだけ true。
    @Published private(set) var experimentalEnabled: Bool

    private let clock: TimeSource
    private let http: HTTPClient
    private let registry: SourceRegistry
    private var timer: Timer?
    private static let defaultsKey = "serviceConfigs.v1"
    private static let experimentalKey = "experimental.enabled.v1"

    init(clock: TimeSource = SystemClock(), http: HTTPClient = URLSessionClient(),
         registry: SourceRegistry = .standard) {
        self.clock = clock
        self.http = http
        self.registry = registry
        self.experimentalEnabled = UserDefaults.standard.bool(forKey: Self.experimentalKey)
        self.now = clock.now
        // 最初は何も追加されていない（未設定）。勝手に取得しない。
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([ServiceConfig].self, from: data) {
            self.configs = saved
        } else {
            self.configs = []
        }
        reloadLocalFiles()
        // 分単位の表示更新と、手元のファイルの読み直しだけ。ネットワークは使わない。
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func tick() {
        now = clock.now
        reloadLocalFiles()
    }

    // MARK: - 表示用

    private var rows: [Row] {
        configs.compactMap { c in
            guard let entry = Catalog.entry(c.catalogID) else { return nil }
            let snap = snapshots[c.id]
            return Row(config: c, entry: entry, snapshot: snap, state: snap?.state(at: now) ?? .noData)
        }
    }

    var limitedRows: [Row] {
        rows.filter { row in
            switch row.state {
            case .limited, .resetEstimatePassed: return true
            default: return false
            }
        }.sorted { a, b in
            func key(_ s: DisplayState) -> Date {
                if case let .limited(at) = s { return at }
                return .distantPast
            }
            return key(a.state) < key(b.state)
        }
    }

    var availableRows: [Row] {
        rows.filter { if case .available = $0.state { return true } else { return false } }
    }

    var creditRows: [Row] {
        rows.filter { if case .credit = $0.state { return true } else { return false } }
    }

    /// メニューバーの文字。制限中が無いときは nil（アプリのアイコンだけ出す）。
    var menuText: String? {
        let snaps = configs.compactMap { snapshots[$0.id] }
        guard let at = Aggregator.earliestRecovery(snaps, now: now) else { return nil }
        return RemainingFormat.text(until: at, now: now)
    }

    func error(for id: String) -> String? { errors[id] }
    func isRefreshing(_ id: String) -> Bool { refreshing.contains(id) }

    // MARK: - 取得

    /// 手元のファイルを読むだけ（通信しない）ので、自動で読み直してよい。
    func reloadLocalFiles() {
        for c in configs {
            guard let entry = Catalog.entry(c.catalogID), entry.kind == .claudeStatusline else { continue }
            apply(configID: c.id) { try StatuslineSource().read() }
        }
    }

    /// 通信を伴う取得は、利用者が更新ボタンを押したときだけ。
    func refresh(_ config: ServiceConfig) async {
        guard let entry = Catalog.entry(config.catalogID) else { return }
        refreshing.insert(config.id)
        defer { refreshing.remove(config.id) }
        do {
            if entry.tier == .experimental && !experimentalEnabled {
                throw SourceError.notAvailable("実験的な取得がオフです（管理 → 設定 でオンにできます）")
            }
            guard let source = registry.source(for: entry.kind) else {
                throw SourceError.notAvailable("この取得方法はまだ入っていません")
            }
            let result = try await source.fetch(
                entry: entry, config: config,
                context: SourceContext(http: http, secrets: KeychainSecretStore()))
            store(result, for: config.id)
        } catch {
            errors[config.id] = error.localizedDescription
        }
    }

    private func apply(configID: String, _ work: () throws -> SourceResult) {
        do { store(try work(), for: configID) }
        catch { errors[configID] = error.localizedDescription }
    }

    private func store(_ result: SourceResult, for id: String) {
        snapshots[id] = Snapshot(serviceID: id, result: result, fetchedAt: clock.now)
        errors[id] = nil
        now = clock.now
    }

    // MARK: - 操作

    func setExperimental(_ on: Bool) {
        experimentalEnabled = on
        UserDefaults.standard.set(on, forKey: Self.experimentalKey)
    }

    /// 追加メニューに出す候補。実験的なものは、オンのときだけ。
    var addableEntries: [CatalogEntry] {
        Catalog.all.filter { $0.tier == .official || experimentalEnabled }
    }

    func add(_ entry: CatalogEntry) {
        configs.append(ServiceConfig(catalogID: entry.id, paymentURL: entry.defaultPaymentURL ?? ""))
    }

    func remove(_ config: ServiceConfig) {
        Keychain.delete(account: config.id)
        configs.removeAll { $0.id == config.id }
        snapshots[config.id] = nil
        errors[config.id] = nil
    }

    func saveKey(_ key: String, for config: ServiceConfig) {
        do { try Keychain.save(key, account: config.id); errors[config.id] = nil }
        catch { errors[config.id] = error.localizedDescription }
    }

    func hasKey(_ config: ServiceConfig) -> Bool { Keychain.load(account: config.id) != nil }

    /// 支払いページを、利用者が選んだブラウザで開く。アプリの中ではログインも支払いもしない。
    func openPayment(_ config: ServiceConfig) {
        guard let url = URL(string: config.paymentURL), url.scheme == "https" else { return }
        if let id = config.browserBundleID,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
