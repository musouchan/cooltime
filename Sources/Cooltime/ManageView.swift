import SwiftUI
import AppKit
import CooltimeCore

struct ManageView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: UUID?
    @State private var adding = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
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
                        if let id = selection, let a = model.accounts.first(where: { $0.id == id }) {
                            selection = nil
                            model.remove(a)
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selection == nil).accessibilityLabel("削除")
                    Spacer()
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            if let id = selection, let item = model.items.first(where: { $0.id == id }) {
                DetailView(item: item).id(id)
            } else {
                Text(model.accounts.isEmpty ? "「＋」から、使っているサービスを追加してください" : "サービスを選んでください")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $adding) { AddServiceView { selection = $0 } }
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
            Text(item.service.method == .apiKey ? "公式APIから取得" : item.service.method == .codexAppServer ? "Codexから取得" : "ステータスラインから取得")
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Claude Code の設定（自分で行います）").font(.caption).foregroundStyle(.secondary)
                Text("このアプリは、他のツールの設定を書き換えません。~/.claude/settings.json の statusLine に、下のコマンドを自分で設定してください。すでにステータスラインがある場合は、そのコマンドを引数として渡せば、そのまま表示も続きます。")
                    .font(.callout)
                let cmd = #"{ "statusLine": { "type": "command", "command": "/path/to/cooltime-statusline.sh" } }"#
                Text(cmd).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                Text("スクリプトは README を参照。取得元: \(Paths.statusline(slot: draft.slot).path)").font(.caption).foregroundStyle(.secondary)
            }
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
