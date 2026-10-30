import Foundation
import SwiftUI
import CooltimeCore

struct Item: Identifiable {
    let account: Account
    let service: ServiceDef
    let snapshot: Snapshot?
    let state: QuotaState
    var id: UUID { account.id }

    var title: String { account.name.isEmpty ? service.name : "\(service.name) · \(account.name)" }
}

private struct Stored: Codable {
    var accounts: [Account]
    var snapshots: [String: Snapshot]
}

@MainActor
final class AppModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published private var snapshots: [UUID: Snapshot] = [:]
    @Published var errors: [UUID: String] = [:]
    @Published var refreshing: Set<UUID> = []
    @Published private(set) var now: Date

    let clock: Clock

    init(clock: Clock = SystemClock()) {
        self.clock = clock
        self.now = clock.now
        load()
        reloadFiles()
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
    }

    // MARK: 一覧

    var items: [Item] {
        accounts.compactMap { a in
            guard let s = Catalog.service(a.serviceID) else { return nil }
            let snap = snapshots[a.id]
            return Item(account: a, service: s, snapshot: snap, state: evaluate(snap, now: now))
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
            if let s = try? Fetchers.readClaude(slot: a.slot) {
                if snapshots[a.id] != s { snapshots[a.id] = s; save() }
                errors[a.id] = nil
            }
        }
    }

    /// 通信を伴う取得。更新ボタンを押したときだけ呼ぶ。
    func refresh(_ account: Account) async {
        guard let service = Catalog.service(account.serviceID), !refreshing.contains(account.id) else { return }
        refreshing.insert(account.id)
        defer { refreshing.remove(account.id) }
        do {
            snapshots[account.id] = try await Fetchers.fetch(account: account, service: service)
            errors[account.id] = nil
            save()
        } catch {
            errors[account.id] = error.localizedDescription
        }
        now = clock.now
    }

    func refreshAll() async {
        for a in accounts { await refresh(a) }
    }

    // MARK: 追加・削除・保存

    @discardableResult
    func add(serviceID: String) -> Account {
        let a = Account(serviceID: serviceID)
        accounts.append(a)
        save()
        return a
    }

    func update(_ a: Account) {
        guard let i = accounts.firstIndex(where: { $0.id == a.id }) else { return }
        accounts[i] = a
        save()
    }

    func remove(_ a: Account) {
        Keychain.delete(a.id)
        accounts.removeAll { $0.id == a.id }
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
        snapshots = Dictionary(uniqueKeysWithValues: stored.snapshots.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    private func save() {
        let stored = Stored(accounts: accounts, snapshots: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key.uuidString, $0.value) }))
        if let data = try? JSONEncoder.cooltime.encode(stored) { try? data.write(to: Paths.state, options: .atomic) }
    }
}

extension JSONEncoder {
    static var cooltime: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }
}
extension JSONDecoder {
    static var cooltime: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }
}
