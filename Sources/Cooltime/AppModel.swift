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
    /// 手動記録はAPI取得結果とは分けて、確認日時と情報源を保管する。
    var manualObservations: [String: [ManualObservation]]?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published private var snapshots: [UUID: Snapshot] = [:]
    @Published var errors: [UUID: String] = [:]
    @Published private(set) var manualObservations: [UUID: [ManualObservation]] = [:]
    @Published var refreshing: Set<UUID> = []
    @Published private(set) var now: Date
    /// 管理画面で選ばれているアカウント。
    @Published var selected: UUID?
    /// 使用状況の記録。Mac の中だけに保存する。
    @Published private(set) var history: UsageHistory
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
        self.history = UsageHistory(startedAt: clock.now)
        load()
        loadHistory()
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
        let before = history.open.count
        history.closeFinished(now: clock.now)
        if history.open.count != before { saveHistory() }
    }

    /// 取得できた数字を、記録に足す。
    private func record(_ account: Account, _ snapshot: Snapshot) {
        if history.observe(account: account.id, serviceID: account.serviceID, snapshot: snapshot, now: clock.now) {
            saveHistory()
        }
    }

    /// 振り返りに出す名前。
    func displayName(_ id: UUID) -> String {
        items.first { $0.id == id }?.title ?? "削除したサービス"
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Paths.history),
              let h = try? JSONDecoder.cooltime.decode(UsageHistory.self, from: data) else { return }
        history = h
    }

    private func saveHistory() {
        if let data = try? JSONEncoder.cooltime.encode(history) { try? data.write(to: Paths.history, options: .atomic) }
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
        items.filter { $0.service.method != .manual && ($0.service.kind == .credit || $0.snapshot?.credit != nil) }
    }

    var manualCredits: [Item] { items.filter { $0.service.method == .manual } }

    func untilDate(_ i: Item) -> Date {
        if case .limited(let d) = i.state { return d }
        return .distantFuture
    }

    /// メニューバーに出すもの（キャラクターと、一番大事な1つの数字）。
    var menuBarDisplay: MenuBarDisplay {
        makeMenuBarDisplay(items.filter { $0.service.method != .manual }.map { MenuBarCandidate(state: $0.state, snapshot: $0.snapshot, fetchFailed: $0.fetchError != nil, source: $0.service.id) })
    }

    /// メニューバーにマウスを乗せたときの説明。
    var menuBarTooltip: String {
        let list = limited
        if list.isEmpty { return "制限中のものはありません" }
        return list.map { i in
            let label = i.snapshot?.windows.filter { $0.isExhausted }
                .max { ($0.resetsAt ?? .distantPast) < ($1.resetsAt ?? .distantPast) }?.label
            return "\(i.title)\(label.map { " · \($0)" } ?? "")  \(formatRemaining(until: untilDate(i), now: now))"
        }.joined(separator: "\n")
    }

    /// 管理画面の「キャラクター」の行（アカウントではないので、決まった ID で選ぶ）。
    static let characterPane = UUID(uuidString: "00000000-0000-0000-0000-00000000C4A2")!

    // MARK: 取得

    /// 手元のファイルを読むだけのもの。
    func reloadFiles() {
        for a in accounts where Catalog.service(a.serviceID)?.method == .statuslineFile {
            // /usage とステータスラインの、新しい方を使う。
            if let s = try? Fetchers.readClaude(slot: a.slot),
               s.fetchedAt > (snapshots[a.id]?.fetchedAt ?? .distantPast) {
                snapshots[a.id] = s
                record(a, s)
                errors[a.id] = nil
                save()
            }
        }
    }

    /// 通信を伴う取得。更新ボタンを押したときだけ呼ぶ。
    func refresh(_ account: Account) async {
        guard let service = Catalog.service(account.serviceID), service.method != .manual,
              !refreshing.contains(account.id) else { return }
        lastAuto[account.id] = clock.now
        refreshing.insert(account.id)
        defer { refreshing.remove(account.id) }
        do {
            let result = try await Fetchers.fetch(account: account, service: service)
            // 古い記録で、新しいデータを上書きしない。
            if result.snapshot.fetchedAt >= (snapshots[account.id]?.fetchedAt ?? .distantPast) {
                snapshots[account.id] = result.snapshot
                record(account, result.snapshot)
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
        for a in accounts where Catalog.service(a.serviceID)?.method != .manual { await refresh(a) }
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
        guard let identity, let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        var changed = false
        if accounts[i].name.isEmpty, let name = identity.displayName {
            accounts[i].name = name
            if let t = identity.type { accounts[i].type = t }
            changed = true
        }
        // プランは、取れたときだけ（本人が選んだものは、上書きしない）
        if accounts[i].planID == nil,
           let plan = PlanCatalog.match(serviceID: accounts[i].serviceID, planName: identity.plan) {
            accounts[i].planID = plan.id
            changed = true
        }
        if changed { save() }
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

    /// 画面またはCSVから確認した記録のみ。自動APIのデータとして扱わない。
    func importManual(_ account: Account, observations: [ManualObservation]) throws {
        guard Catalog.service(account.serviceID)?.method == .manual,
              accounts.contains(where: { $0.id == account.id }) else {
            throw ManualImportError.invalid("手動記録対象ではありません")
        }
        guard !observations.isEmpty else { throw ManualImportError.invalid("記録がありません") }
        // 同時刻の手動修正は新しい入力を採用する。
        var saved = manualObservations[account.id] ?? []
        for observation in observations {
            saved.removeAll { $0.observedAt == observation.observedAt }
            saved.append(observation)
        }
        saved.sort { $0.observedAt > $1.observedAt }
        manualObservations[account.id] = Array(saved.prefix(500))
        if let latest = manualObservations[account.id]?.first {
            snapshots[account.id] = latest.snapshot
        }
        errors[account.id] = nil
        save()
    }

    func remove(_ a: Account) {
        Keychain.delete(a.id)
        history.forget(account: a.id)
        saveHistory()
        accounts.removeAll { $0.id == a.id }
        dismissed.insert(a.serviceID)
        snapshots[a.id] = nil
        manualObservations[a.id] = nil
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
        manualObservations = Dictionary(uniqueKeysWithValues: (stored.manualObservations ?? [:]).compactMap { k, v in
            UUID(uuidString: k).map { ($0, v.sorted { $0.observedAt > $1.observedAt }) }
        })
        for (id, history) in manualObservations {
            if let latest = history.first { snapshots[id] = latest.snapshot }
        }
    }

    private func save() {
        let stored = Stored(accounts: accounts, snapshots: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key.uuidString, $0.value) }),
                        dismissed: Array(dismissed),
                            manualObservations: Dictionary(uniqueKeysWithValues: manualObservations.map { ($0.key.uuidString, $0.value) }))
        if let data = try? JSONEncoder.cooltime.encode(stored) { try? data.write(to: Paths.state, options: .atomic) }
    }
}

extension JSONEncoder {
    static var cooltime: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }
}
extension JSONDecoder {
    static var cooltime: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }
}
