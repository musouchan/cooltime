import Foundation
import SwiftUI
import CooltimeCore

struct Item: Identifiable {
    let account: Account
    let service: ServiceDef
    let snapshot: Snapshot?
    let state: QuotaState
    /// 同じサービスに複数のアカウントがあるときだけ、アカウント名を出して見分ける。
    let showsAccountName: Bool
    /// 最新の取得に失敗しているときの理由。あるときは、数字は古い。
    let fetchError: String?
    var id: UUID { account.id }

    var title: String { showsAccountName && !account.name.isEmpty ? "\(service.name) · \(account.name)" : service.name }
    /// 法人と分かっているときだけ、印を出す（個人は、出さない）。
    var isBusiness: Bool { account.type == .business }
}

private struct Stored: Codable {
    var accounts: [Account]
    var snapshots: [String: Snapshot]
    /// 自分で削除したサービス。自動検出で勝手に戻さない。
    var dismissed: [String]?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published private var snapshots: [UUID: Snapshot] = [:]
    @Published var errors: [UUID: String] = [:]
    @Published var refreshing: Set<UUID> = []
    @Published private(set) var now: Date
    /// 管理画面で選ばれているアカウント。
    @Published var selected: UUID?
    private var dismissed: Set<String> = []
    /// 自動更新を最後に行った時刻と、最後に見た合図の時刻。
    private var lastAuto: [UUID: Date] = [:]
    private var watcher: ActivityWatcher?
    private var activityTasks: [String: Task<Void, Never>] = [:]
    private var lastPing: Date?

    let clock: Clock

    init(clock: Clock = SystemClock()) {
        self.clock = clock
        self.now = clock.now
        load()
        autoDetect()
        reloadFiles()
        lastPing = pingDate()
        autoRefresh()
        startWatching()
        Task { [weak self] in
            // 分単位で静かに更新する。手元のファイルは自動で読み直す（通信なし）。
            while true {
                try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)
                self?.tick()
            }
        }
    }

    func tick() {
        reloadFiles()
        now = clock.now
        autoRefresh()
    }

    /// Claude Code（ターミナルでもデスクトップの Code タブでも）と Codex は、使うと記録のファイルを更新する。
    /// その更新を合図に、返事が終わって少し経ったら、そのサービスだけすぐ更新する。
    private func startWatching() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        watcher = ActivityWatcher { [weak self] paths in
            Task { @MainActor in self?.noteActivity(paths) }
        }
        watcher?.start(paths: ["\(home)/.claude/projects", "\(home)/.codex/sessions"])
    }

    private func noteActivity(_ paths: [String]) {
        var services = Set<String>()
        for p in paths where p.hasSuffix(".jsonl") {
            if p.contains("/.claude/projects/") {
                // 自分の確認（/usage）が残す記録では、動かさない。
                if !p.contains("Library-Application-Support-Cooltime") { services.insert("claude") }
            } else if p.contains("/.codex/sessions/") {
                services.insert("codex")
            }
        }
        for s in services { scheduleActivityRefresh(s) }
    }

    /// 更新が5秒止まったら（返事が終わったら）、1回だけ更新する。
    private func scheduleActivityRefresh(_ serviceID: String) {
        activityTasks[serviceID]?.cancel()
        activityTasks[serviceID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            for a in self.accounts where a.serviceID == serviceID && (serviceID != "claude" || a.slot == "default") {
                // 失敗が続くものと、直前に更新したものは、動かさない（暴走を防ぐ）。
                if self.errors[a.id] != nil { continue }
                if self.clock.now.timeIntervalSince(self.lastAuto[a.id] ?? .distantPast) < 20 { continue }
                await self.refresh(a)
            }
        }
    }

    private func pingDate() -> Date? {
        try? Paths.claudePing.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// 自動で更新するもの: Claude（公式の Claude Code の /usage）と、Codex（app-server）。
    /// 1分おき。Claude Code の返事が終わった合図があれば、Claude はすぐ。
    /// 失敗が続くものは、問い合わせすぎないよう5分おきに落とす。
    /// APIキー系は、更新ボタンのときだけ。
    private func autoRefresh() {
        var pinged = false
        if let ping = pingDate(), ping > (lastPing ?? .distantPast) {
            lastPing = ping
            pinged = true
        }
        for a in accounts {
            guard let s = Catalog.service(a.serviceID) else { continue }
            let auto = (s.method == .statuslineFile && a.slot == "default") || s.method == .codexAppServer
            guard auto else { continue }
            let interval: TimeInterval = errors[a.id] != nil ? 5 * 60 : 60
            let due = clock.now.timeIntervalSince(lastAuto[a.id] ?? .distantPast) >= interval
            if due || (pinged && a.serviceID == "claude") {
                Task { await refresh(a) }
            }
        }
    }

    // MARK: 一覧

    var items: [Item] {
        accounts.compactMap { a in
            guard let s = Catalog.service(a.serviceID) else { return nil }
            let snap = snapshots[a.id]
            let multiple = accounts.filter { $0.serviceID == a.serviceID }.count > 1
            return Item(account: a, service: s, snapshot: snap, state: evaluate(snap, now: now), showsAccountName: multiple,
                        fetchError: errors[a.id])
        }
    }

    var subscriptions: [Item] { items.filter { $0.service.kind == .subscription } }

    var limited: [Item] {
        subscriptions.filter { if case .limited = $0.state { return true } else { return false } }
            .sorted { untilDate($0) < untilDate($1) }
    }
    var stale: [Item] {
        subscriptions.filter { if case .stale = $0.state { return true } else { return false } }
    }
    var available: [Item] {
        subscriptions.filter { $0.state == .available || $0.state == .unset }
    }
    var credits: [Item] {
        items.filter { $0.service.kind == .credit || $0.snapshot?.credit != nil }
    }

    func untilDate(_ i: Item) -> Date {
        if case .limited(let d) = i.state { return d }
        return .distantFuture
    }

    var menuBarPick: MenuBarPick? {
        pickForMenuBar(subscriptions.map { (id: $0.id, state: $0.state) })
    }

    // MARK: 取得

    /// 手元のファイルを読むだけのもの。
    func reloadFiles() {
        for a in accounts where Catalog.service(a.serviceID)?.method == .statuslineFile {
            // /usage とステータスラインの、新しい方を使う。
            if let s = try? Fetchers.readClaude(slot: a.slot),
               s.fetchedAt > (snapshots[a.id]?.fetchedAt ?? .distantPast) {
                snapshots[a.id] = s
                errors[a.id] = nil
                save()
            }
        }
    }

    /// 通信を伴う取得。更新ボタンを押したときだけ呼ぶ。
    func refresh(_ account: Account) async {
        guard let service = Catalog.service(account.serviceID), !refreshing.contains(account.id) else { return }
        lastAuto[account.id] = clock.now
        refreshing.insert(account.id)
        defer { refreshing.remove(account.id) }
        do {
            let result = try await Fetchers.fetch(account: account, service: service)
            // 古い記録で、新しいデータを上書きしない。
            if result.snapshot.fetchedAt >= (snapshots[account.id]?.fetchedAt ?? .distantPast) {
                snapshots[account.id] = result.snapshot
            }
            apply(result.identity, to: account.id)
            errors[account.id] = result.warning
            save()
        } catch {
            errors[account.id] = error.localizedDescription
        }
        now = clock.now
    }

    func refreshAll() async {
        for a in accounts { await refresh(a) }
    }

    // MARK: 自動検出

    /// ログイン済みのツールを、この Mac のファイルの有無だけで見つけて追加する（通信なし・中身は読まない）。
    /// 自分で削除したものは、戻さない。
    func autoDetect() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var found: [String] = []
        if fm.fileExists(atPath: home.appendingPathComponent(".claude.json").path)
            || fm.fileExists(atPath: home.appendingPathComponent(".claude").path) { found.append("claude") }
        if fm.fileExists(atPath: home.appendingPathComponent(".codex/auth.json").path) { found.append("codex") }

        for id in found where !dismissed.contains(id) && !accounts.contains(where: { $0.serviceID == id }) {
            add(serviceID: id)
        }
    }

    private func apply(_ identity: AccountIdentity?, to id: UUID) {
        guard let identity, let i = accounts.firstIndex(where: { $0.id == id }),
              accounts[i].name.isEmpty, let name = identity.displayName else { return }
        accounts[i].name = name
        if let t = identity.type { accounts[i].type = t }
        save()
    }

    // MARK: 追加・削除・保存

    @discardableResult
    func add(serviceID: String) -> Account {
        let a = Account(serviceID: serviceID)
        accounts.append(a)
        dismissed.remove(serviceID)
        if serviceID == "claude" { apply(Fetchers.claudeIdentity(), to: a.id) }
        save()
        return accounts.first { $0.id == a.id } ?? a
    }

    func update(_ a: Account) {
        guard let i = accounts.firstIndex(where: { $0.id == a.id }) else { return }
        accounts[i] = a
        save()
    }

    func remove(_ a: Account) {
        Keychain.delete(a.id)
        accounts.removeAll { $0.id == a.id }
        dismissed.insert(a.serviceID)
        snapshots[a.id] = nil
        errors[a.id] = nil
        save()
    }

    func paymentURL(_ a: Account) -> URL? {
        let raw = a.paymentURL.trimmingCharacters(in: .whitespaces)
        if let u = URL(string: raw), ["http", "https"].contains(u.scheme), !raw.isEmpty { return u }
        return Catalog.service(a.serviceID).flatMap { URL(string: $0.defaultPaymentURL) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Paths.state),
              let stored = try? JSONDecoder.cooltime.decode(Stored.self, from: data) else { return }
        accounts = stored.accounts
        dismissed = Set(stored.dismissed ?? [])
        snapshots = Dictionary(uniqueKeysWithValues: stored.snapshots.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    private func save() {
        let stored = Stored(accounts: accounts, snapshots: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key.uuidString, $0.value) }),
                        dismissed: Array(dismissed))
        if let data = try? JSONEncoder.cooltime.encode(stored) { try? data.write(to: Paths.state, options: .atomic) }
    }
}

extension JSONEncoder {
    static var cooltime: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }
}
extension JSONDecoder {
    static var cooltime: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }
}
