import SwiftUI
import AppKit
import CooltimeCore

struct ManageView: View {
    @EnvironmentObject var model: AppModel
    @State private var adding = false

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
                }
                Divider()
                HStack {
                    Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("サービスを追加")
                    Button {
                        if let id = model.selected, let a = model.accounts.first(where: { $0.id == id }) {
                            model.selected = nil
                            model.remove(a)
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(model.selected == nil).accessibilityLabel("削除")
                    Spacer()
                    Text(versionText).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            if let id = model.selected, let item = model.items.first(where: { $0.id == id }) {
                DetailView(item: item).id(id)
            } else {
                Text(model.accounts.isEmpty ? "「＋」から、使っているサービスを追加してください" : "サービスを選んでください")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $adding) { AddServiceView { model.selected = $0 } }
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
                Text(item.account.name.isEmpty ? item.account.type.label : "\(item.account.name) \(item.account.type.label)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(sidebarValue(item)).font(.caption).foregroundStyle(.secondary)
        }
        .tag(item.id)
    }

    private func sidebarValue(_ item: Item) -> String {
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

private struct DetailView: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    @State private var draft: Account
    @State private var apiKey = ""
    @State private var showStatuslineHelp = false

    init(item: Item) {
        self.item = item
        _draft = State(initialValue: item.account)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let snap = item.snapshot { windows(snap) }
                if let err = model.errors[item.id] { Text(err).foregroundStyle(.red).font(.callout) }
                setup
                settings
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(service: item.service, size: 34)
            VStack(alignment: .leading) {
                Text(item.service.name).font(.title3).fontWeight(.semibold)
                Text(item.service.hint).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.service.method == .apiKey ? "公式APIから取得" : item.service.method == .codexAppServer ? "Codexから取得" : "Claude Codeから取得")
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.quaternary))
        }
    }

    private func windows(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !snap.windows.isEmpty { Text("利用枠").font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(snap.windows.enumerated()), id: \.offset) { _, w in windowCard(w) }
            }
            if let c = snap.credit {
                Text("クレジット残高 \(formatMoney(c))").font(.callout)
            }
            Text("取得 \(formatClock(snap.fetchedAt, now: model.now))").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func windowCard(_ w: UsageWindow) -> some View {
        let state = evaluate(Snapshot(windows: [w], fetchedAt: item.snapshot?.fetchedAt ?? model.now), now: model.now)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(w.label).fontWeight(.semibold)
                Spacer()
                StateGlyph(state: state)
                Text(stateWord(state)).font(.caption)
            }
            switch state {
            case .limited(let u): Text(formatRemaining(until: u, now: model.now)).font(.title2).fontWeight(.semibold)
            case .stale: Text("リセット目安です").font(.title3)
            default: Text(availableSummary(Snapshot(windows: [w], fetchedAt: model.now)) ?? "—").font(.title2).fontWeight(.semibold)
            }
            if let r = w.resetsAt { Text("リセット \(formatClock(r, now: model.now)) · 公式").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    @ViewBuilder private var setup: some View {
        switch item.service.method {
        case .statuslineFile:
            StatuslineSetupView()
        case .codexAppServer:
            HStack {
                Button { Task { await model.refresh(item.account) } } label: { Label("更新", systemImage: "arrow.clockwise") }
                    .disabled(model.refreshing.contains(item.id))
                Text("更新ボタンを押したときだけ、Codex に問い合わせます。").font(.caption).foregroundStyle(.secondary)
            }
        case .apiKey:
            VStack(alignment: .leading, spacing: 6) {
                Text(item.service.apiKeyHelp ?? "APIキー").font(.caption).foregroundStyle(.secondary)
                HStack {
                    SecureField(Keychain.has(item.id) ? "保存済み（Keychain）" : "APIキーを貼り付け", text: $apiKey)
                    Button("保存して取得") {
                        if !apiKey.isEmpty { Keychain.set(apiKey, for: item.id); apiKey = "" }
                        Task { await model.refresh(item.account) }
                    }
                    .disabled(model.refreshing.contains(item.id) || (apiKey.isEmpty && !Keychain.has(item.id)))
                }
                Text("APIキーは Keychain にだけ保存します。画面には再表示しません。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("アカウントと支払い").font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("名前")
                    TextField("例: Max / 会社用", text: $draft.name)
                }
                GridRow {
                    Text("個人／法人")
                    Picker("", selection: $draft.type) {
                        ForEach(AccountType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                if item.service.method == .statuslineFile {
                    GridRow {
                        Text("取得元の識別名")
                        TextField("default", text: $draft.slot)
                    }
                }
                GridRow {
                    Text("支払いページ")
                    TextField(item.service.defaultPaymentURL, text: $draft.paymentURL)
                }
            }
            HStack {
                Button("保存") { model.update(draft) }.disabled(draft == item.account)
                Button { if let u = model.paymentURL(draft) { NSWorkspace.shared.open(u) } } label: {
                    Label("支払いページを開く", systemImage: "arrow.up.right.square")
                }
            }
        }
    }
}

private struct StatuslineSetupView: View {
    @State private var isSet = StatuslineSetup.isSet()
    @State private var change: StatuslineConfig.Change?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code との連携").font(.caption).foregroundStyle(.secondary)
            if isSet {
                HStack {
                    Image(systemName: "checkmark.circle").foregroundStyle(.green)
                    Text("設定済み。返事が終わるたびに、すぐ更新されます。")
                    Spacer()
                    Button("元に戻す") { run { try StatuslineSetup.revert() } }
                }
            } else {
                Text("使用量は、公式の Claude Code（/usage）で5分おきに自動で確認します。デスクトップアプリやターミナルで返事が終わるたびにすぐ更新するには、Claude Code に合図の設定を足します。変更内容を確認してから設定し、元のファイルはバックアップを取ります。")
                    .font(.callout)
                Button("設定する…") {
                    do { change = try StatuslineSetup.preview() } catch { message = error.localizedDescription }
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
