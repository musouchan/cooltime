import SwiftUI
import RecoveryCore

struct ManagerView: View {
    @ObservedObject var store: Store
    @State private var selection: String?
    @State private var showExperimentalConfirm = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("サブスク（プランの利用枠）") {
                    ForEach(store.configs.filter { !(Catalog.entry($0.catalogID)?.isCreditOnly ?? false) }) { sidebarRow($0) }
                }
                Section("API・クレジット") {
                    ForEach(store.configs.filter { Catalog.entry($0.catalogID)?.isCreditOnly ?? false }) { sidebarRow($0) }
                }
                Section("設定") {
                    Toggle("実験的な取得を使う", isOn: Binding(
                        get: { store.experimentalEnabled },
                        set: { on in
                            if on { showExperimentalConfirm = true } else { store.setExperimental(false) }
                        }))
                    Text("公式ではない方法（ブラウザのCookieなど）で取得するサービスを、追加できるようになります。既定はオフです。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .confirmationDialog("実験的な取得をオンにしますか？", isPresented: $showExperimentalConfirm) {
                Button("オンにする") { store.setExperimental(true) }
                Button("やめる", role: .cancel) {}
            } message: {
                Text("サービスの公式ではない仕組みを使うため、予告なく取得できなくなることがあります。サービスの規約に反する可能性もあります。ログイン情報は Keychain にだけ保存し、更新ボタンを押したときだけ、そのサービスに送ります。")
            }
            .toolbar {
                ToolbarItem {
                    Menu {
                        ForEach(store.addableEntries) { entry in
                            Button(entry.tier == .experimental ? "\(entry.name)（実験的）" : entry.name) {
                                store.add(entry)
                            }
                        }
                    } label: { Label("サービスを追加", systemImage: "plus") }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            if let id = selection, let idx = store.configs.firstIndex(where: { $0.id == id }) {
                DetailView(store: store, config: $store.configs[idx])
            } else {
                Text("左のリストからサービスを選ぶか、＋で追加してください")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sidebarRow(_ c: ServiceConfig) -> some View {
        VStack(alignment: .leading) {
            Text(Catalog.entry(c.catalogID)?.name ?? c.catalogID)
            Text([c.account, c.kind.label].filter { !$0.isEmpty }.joined(separator: " ・ "))
                .font(.caption).foregroundStyle(.secondary)
        }
        .tag(c.id)
    }
}

private struct DetailView: View {
    @ObservedObject var store: Store
    @Binding var config: ServiceConfig
    @State private var apiKey = ""

    private var entry: CatalogEntry? { Catalog.entry(config.catalogID) }

    var body: some View {
        Form {
            Section {
                Text(entry?.name ?? "").font(.headline)
                Text(entry?.note ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Section("アカウント") {
                TextField("アカウント名（例: 個人 / RETHIC）", text: $config.account)
                Picker("個人／法人", selection: $config.kind) {
                    ForEach(AccountKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("プラン", text: $config.plan)
            }
            if entry?.needsAPIKey == true {
                Section("APIキー") {
                    SecureField(store.hasKey(config) ? "保存済み（変更するときだけ入力）" : "APIキー", text: $apiKey)
                    Text("Keychain にだけ保存します。ファイルやログには残しません。更新ボタンを押したときだけ、このサービスの公式APIに送ります。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("保存") { store.saveKey(apiKey, for: config); apiKey = "" }
                        .disabled(apiKey.isEmpty)
                }
            }
            Section("支払い") {
                TextField("支払いページのURL（https）", text: $config.paymentURL)
                Button("支払いページを開く ↗") { store.openPayment(config) }
                    .disabled(URL(string: config.paymentURL)?.scheme != "https")
            }
            Section("取得") {
                Button("今すぐ更新") { Task { await store.refresh(config) } }
                    .disabled(store.isRefreshing(config.id))
                if let err = store.error(for: config.id) {
                    Text(err).foregroundStyle(.orange)
                }
            }
            Section {
                Button("このサービスを削除", role: .destructive) { store.remove(config) }
            }
        }
        .formStyle(.grouped)
    }
}
