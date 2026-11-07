import SwiftUI
import AppKit
import CooltimeCore

struct ManageView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var actions: AppActions
    @State private var adding = false
    @State private var pendingDelete: Account?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $model.selected) {
                    Section("サブスク（プランの利用枠）") {
                        ForEach(model.subscriptions) { sidebarRow($0) }
                    }
                    Section("API・クレジット") {
                        ForEach(model.items.filter { $0.service.kind == .credit }) { sidebarRow($0) }
                    }
                    Section("表示") {
                        Label("表示の設定", systemImage: "slider.horizontal.3").tag(AppModel.characterPane)
                    }
                }
                Divider()
                HStack {
                    Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("サービスを追加")
                    Button {
                        pendingDelete = model.accounts.first(where: { $0.id == model.selected })
                    } label: { Image(systemName: "minus") }
                        .disabled(!model.accounts.contains { $0.id == model.selected }).accessibilityLabel("削除")
                    Spacer()
                    Text(versionText).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(8)
                HStack {
                    Button { actions.openReview() } label: { Label("振り返り", systemImage: "chart.bar") }
                    Button { Task { await model.refreshAll() } } label: { Label("すべて更新", systemImage: "arrow.clockwise") }
                        .help("すべてのサービスを今すぐ更新します（通信します）")
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
                if updater.canUpdate { updateBar }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            if model.selected == AppModel.characterPane {
                CharacterSettingsView().environmentObject(model)
            } else if let id = model.selected, let item = model.items.first(where: { $0.id == id }) {
                DetailView(item: item).id(id)
            } else {
                Text(model.accounts.isEmpty ? "「＋」から、使っているサービスを追加してください" : "サービスを選んでください")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $adding) { AddServiceView { model.selected = $0 } }
        .confirmationDialog("このサービスを削除しますか？", isPresented: Binding(get: { pendingDelete != nil },
                                                                      set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { a in
            Button("削除", role: .destructive) {
                model.selected = nil
                model.remove(a)
            }
            Button("キャンセル", role: .cancel) {}
        } message: { a in
            let name = Catalog.service(a.serviceID)?.name ?? ""
            Text("「\(name)」の設定と、取得したデータを削除します。保存したAPIキーも、Keychain から削除します。自動で見つかったものは、次の起動でも戻りません（「＋」からいつでも追加できます）。")
        }
    }

    /// 更新の確認も、入れ替えも、ボタンを押したときだけ。
    private var updateBar: some View {
        HStack {
            switch updater.state {
            case .idle, .upToDate, .failed:
                Button("更新を確認") { Task { await updater.check() } }
                switch updater.state {
                case .upToDate: Text("最新です").font(.caption2).foregroundStyle(.secondary)
                case .failed(let m): Text(m).font(.caption2).foregroundStyle(.red).lineLimit(2)
                default: EmptyView()
                }
            case .checking:
                Text("確認中…").font(.caption2).foregroundStyle(.secondary)
            case .available(let v):
                Button("\(v) に更新して再起動") { Task { await updater.install() } }
            case .installing:
                Text("入れ替え中…").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.bottom, 8)
    }

    /// 「Cooltime 0.1.0 (abc1234)」。タグのビルドは版、ほかは短いコミット ID が付く。
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let v = info?["CFBundleShortVersionString"] as? String else { return "開発版" }
        let b = info?["CFBundleVersion"] as? String
        return "Cooltime \(v)" + (b.map { $0 == v ? "" : " (\($0))" } ?? "")
    }

    private func sidebarRow(_ item: Item) -> some View {
        HStack {
            AppIconView(service: item.service, size: 20)
            VStack(alignment: .leading) {
                Text(item.service.name)
                if !item.account.name.isEmpty || item.isBusiness {
                    Text([item.account.name, item.isBusiness ? "法人" : ""].filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(sidebarValue(item)).font(.caption).foregroundStyle(.secondary)
        }
        .tag(item.id)
    }

    private func sidebarValue(_ item: Item) -> String {
        if item.fetchError != nil, item.state == .available || item.state == .unset { return "取得失敗" }
        switch item.state {
        case .limited(let u): return formatRemaining(until: u, now: model.now)
        case .stale: return "目安を過ぎた"
        case .unset: return item.snapshot?.credit == nil ? "未取得" : ""
        case .available:
            if let c = item.snapshot?.credit { return formatMoney(c) }
            return item.snapshot.flatMap(availableSummary) ?? "使える"
        }
    }
}

/// カード（薄い背景の、角丸の箱）。
private extension View {
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }
}

/// サービス（アカウント）の詳細。
/// 上から: 見出し（アイコン・サービス名・アカウント名・プラン・請求ページ）→ 利用枠 →（必要なものだけ）APIキー・プラン・連携 → 詳細。
private struct DetailView: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    @State private var draft: Account
    @State private var apiKey = ""
    @State private var showAdvanced = false
    @FocusState private var nameFocused: Bool

    init(item: Item) {
        self.item = item
        _draft = State(initialValue: item.account)
    }

    private var planOptions: [PlanOption] { PlanCatalog.options(for: item.service.id) }
    private var plan: PlanOption? { PlanCatalog.option(serviceID: item.service.id, id: draft.planID) }
    private var billingURL: URL? { model.paymentURL(draft) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                usageCard
                if item.service.method == .apiKey { keyCard }
                if !planOptions.isEmpty { planCard }
                if item.service.method == .statuslineFile { StatuslineSetupView().card() }
                advanced
            }
            .padding(24)
        }
        // 自動で入ったメールアドレスなどを、古い入力欄で上書きしない。
        .onChange(of: item.account) { _, new in draft = new }
    }

    private func commit() {
        if draft != item.account { model.update(draft) }
    }

    // MARK: 見出し

    private var priceText: String? {
        if let yen = draft.monthlyPrice { return "月 ¥\(yen.formatted())" }
        return plan?.priceText
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AppIconView(service: item.service, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.service.name).font(.title2).fontWeight(.semibold)
                // アカウント名は、ここで直接書き換える（保存ボタンは要らない）
                HStack(spacing: 4) {
                    TextField("アカウント名（例: 会社用）", text: $draft.name)
                        .textFieldStyle(.plain).font(.callout)
                        .focused($nameFocused)
                        .onSubmit { commit() }
                    Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 300)
                if let plan {
                    Text([plan.name, priceText].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Button { if let u = billingURL { NSWorkspace.shared.open(u) } } label: {
                Label("請求ページ", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .disabled(billingURL == nil)
            .help("ログイン済みのブラウザで、請求ページを開きます")
        }
        .onChange(of: nameFocused) { _, focused in if !focused { commit() } }
    }

    // MARK: 利用枠

    @ViewBuilder private var fetchedCaption: some View {
        if let at = item.snapshot?.fetchedAt {
            if item.fetchError != nil {
                Text("\(formatClock(at, now: model.now)) 時点（更新に失敗）").font(.caption).foregroundStyle(.orange)
            } else {
                Text("\(formatClock(at, now: model.now)) に取得").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("利用枠").font(.headline)
                Spacer()
                fetchedCaption
            }
            if let err = model.errors[item.id] {
                Text(err).font(.callout).foregroundStyle(.red)
            }
            if let snap = item.snapshot {
                ForEach(Array(snap.windows.enumerated()), id: \.offset) { _, w in
                    WindowBarRow(window: w, now: model.now, dimmed: item.fetchError != nil)
                }
                if let c = snap.credit {
                    HStack {
                        Text("クレジット残高")
                        Spacer()
                        Text(formatMoney(c)).font(.title3).fontWeight(.semibold).monospacedDigit()
                    }
                }
                if snap.windows.isEmpty && snap.credit == nil {
                    Text("取得できる利用枠がありません").foregroundStyle(.secondary)
                }
            } else {
                Text("まだ取得していません。「すべて更新」で取得できます。").foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: APIキー

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APIキー").font(.headline)
            HStack {
                SecureField(Keychain.has(item.id) ? "保存済み（Keychain）" : (item.service.apiKeyHelp ?? "APIキーを貼り付け"), text: $apiKey)
                Button("保存して取得") {
                    if !apiKey.isEmpty { Keychain.set(apiKey, for: item.id); apiKey = "" }
                    Task { await model.refresh(item.account) }
                }
                .disabled(model.refreshing.contains(item.id) || (apiKey.isEmpty && !Keychain.has(item.id)))
            }
            Text("APIキーは、この Mac の Keychain にだけ保存します。").font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    // MARK: プラン

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プラン").font(.headline)
            Picker("プラン", selection: Binding(
                get: { draft.planID ?? "" },
                set: { draft.planID = $0.isEmpty ? nil : $0; model.update(draft) })
            ) {
                if draft.planID == nil { Text("選んでください").tag("") }
                ForEach(planOptions) { Text("\($0.name)（\($0.priceText)）").tag($0.id) }
            }
            .labelsHidden()
            .frame(maxWidth: 280, alignment: .leading)
            Text(draft.planID == nil
                 ? (item.service.id == "claude" ? "Claude のプランは、Claude Code から自動では取れないので、選んでください。" : "プランを選ぶと、月額の目安が出ます。")
                 : "月額は、公式の価格（米ドル）の目安です。円で上書きするときは、「詳細」から。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    // MARK: 詳細（ふだんは使わないもの）

    private func validURL(_ raw: String) -> Bool {
        guard let u = URL(string: raw), ["http", "https"].contains(u.scheme), u.host != nil else { return false }
        return true
    }
    private var urlInvalid: Bool {
        let raw = draft.paymentURL.trimmingCharacters(in: .whitespaces)
        return !raw.isEmpty && !validURL(raw)
    }

    private func field<C: View>(_ title: String, help: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).frame(width: 120, alignment: .leading)
                content()
            }
            if let help { Text(help).font(.caption).foregroundStyle(.secondary).padding(.leading, 132) }
        }
    }

    private var advanced: some View {
        DisclosureGroup("詳細", isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                field("月額（円）", help: "プランの目安を、自分の金額で上書きします（空なら目安）。") {
                    TextField("例: 3000", text: Binding(
                        get: { draft.monthlyPrice.map(String.init) ?? "" },
                        set: { draft.monthlyPrice = Int($0.filter(\.isNumber)) }))
                }
                field("請求ページ", help: urlInvalid ? "https:// から始まるURLを入れてください"
                                                    : "チームや法人のプランなど、請求ページが違うときだけ変えます（空なら、サービスの初期のページ）。") {
                    HStack {
                        TextField(item.service.defaultPaymentURL, text: $draft.paymentURL)
                        Button("初期値に戻す") { draft.paymentURL = "" }.disabled(draft.paymentURL.isEmpty)
                    }
                }
                if item.service.method == .statuslineFile {
                    field("取得元の識別名", help: "Claude のアカウントが複数あるとき、ステータスラインの記録を見分ける名前です。ふつうは、そのままで。") {
                        TextField("default", text: $draft.slot)
                    }
                }
                HStack {
                    Spacer()
                    Button("保存") { model.update(draft) }
                        .disabled(draft == item.account || urlInvalid)
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 4)
    }
}

private struct StatuslineSetupView: View {
    @State private var isSet = StatuslineSetup.isSet()
    @State private var change: StatuslineConfig.Change?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("リアルタイム更新").font(.headline)
                    Text("Claude Code の返事が終わった直後に、更新します。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSet {
                    Label("設定済み", systemImage: "checkmark.circle").foregroundStyle(.green).font(.callout)
                    Button("元に戻す") { run { try StatuslineSetup.revert() } }
                } else {
                    Button("設定する…") {
                        do { change = try StatuslineSetup.preview() } catch { message = error.localizedDescription }
                    }
                }
            }
            if let message { Text(message).font(.callout).foregroundStyle(.red) }
        }
        .sheet(item: Binding(get: { change.map { Wrapper(change: $0) } }, set: { change = $0?.change })) { w in
            VStack(alignment: .leading, spacing: 12) {
                Text("~/.claude/settings.json を変更します").font(.title3).fontWeight(.semibold)
                Text("変更前の statusLine").font(.caption).foregroundStyle(.secondary)
                code(w.change.before)
                Text("変更後の statusLine").font(.caption).foregroundStyle(.secondary)
                code(w.change.after)
                if w.change.addsHook {
                    Text("追加するフック（返事が終わったら Cooltime に合図。通信はしません）").font(.caption).foregroundStyle(.secondary)
                    code(StatuslineSetup.hookCommand)
                }
                Text("すでにステータスラインがある場合は、そのまま表示も続きます。元のファイルは settings.json.cooltime-backup-… として残ります。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("キャンセル") { change = nil }
                    Button("設定する") { let c = w.change; change = nil; run { try StatuslineSetup.apply(c) } }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20).frame(width: 520)
        }
    }

    private struct Wrapper: Identifiable { let change: StatuslineConfig.Change; var id: String { change.after } }

    private func code(_ text: String) -> some View {
        Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
    }

    private func run(_ work: () throws -> Void) {
        do { try work(); message = nil } catch { message = error.localizedDescription }
        isSet = StatuslineSetup.isSet()
    }
}
