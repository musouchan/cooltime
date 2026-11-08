import SwiftUI
import AppKit
import CooltimeCore

/// 管理画面の「設定」。何についての設定かが分かるよう、まとまりごとに、見出しと箱で分ける。
///   メニューバー ／ 表示 ／ iPhone への通知 ／ スマホで見る ／ アプリ
/// （モデルの変化で、キャラクターの一覧まで描き直さないよう、まとまりごとに別の部品にしてある）
@MainActor
struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("設定").font(.title2).fontWeight(.semibold)
                MenuBarGroup()
                DisplayGroup()
                NotifyGroup()
                PhoneGroup()
                AppGroup()
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: 部品

/// 設定のまとまり。見出し（アイコン付き）＋ 薄い背景の箱。
private struct SettingsBox<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }
}

/// 箱の中の、小さな見出し。
private struct SubTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.subheadline).fontWeight(.semibold) }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

// MARK: メニューバー

@MainActor
private struct MenuBarGroup: View {
    @AppStorage(CharacterPrefs.characterKey) private var characterID = "bunny"
    @AppStorage(CharacterPrefs.motionKey) private var motion = MotionSetting.full.rawValue
    @AppStorage(CharacterPrefs.lowPowerKey) private var inLowPower = false
    @AppStorage(CharacterPrefs.compactKey) private var compact = false
    @AppStorage(CharacterPrefs.backgroundKey) private var background = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// いま、動きが控えめ（または止まっている）理由。
    private var reason: String? {
        if reduceMotion { return "「視差効果を減らす」がオンのため、いまは止まっています。" }
        if motion == MotionSetting.still.rawValue { return "「止める」を選んでいるため、止まっています。" }
        if motion == MotionSetting.sometimes.rawValue { return "「ときどきだけ」を選んでいるため、まばたきだけです。" }
        if lowPower && !inLowPower { return "低電力モードがオンのため、いまはまばたきだけです。" }
        return nil
    }

    var body: some View {
        SettingsBox(title: "メニューバー", systemImage: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                SubTitle("キャラクター")
                Note("状態は、色ではなく、耳の形・記号（z と ×）・動きで見分けられます。")
                VStack(spacing: 8) {
                    ForEach(CharacterData.ids, id: \.self) { id in
                        Button { characterID = id } label: { CharacterRow(id: id, selected: characterID == id) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(CharacterData.names[id] ?? id)
                            .accessibilityAddTraits(characterID == id ? [.isSelected] : [])
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SubTitle("動き")
                Picker("動き", selection: $motion) {
                    ForEach(MotionSetting.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                Toggle("低電力モードのときも動かす", isOn: $inLowPower)
                if let reason { Label(reason, systemImage: "info.circle").font(.callout) }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SubTitle("見た目")
                Toggle("うすい丸い背景を付ける", isOn: $background)
                Toggle("せまくする（サービスのアイコンなし・短い文字）", isOn: $compact)
                Note("メニューバーが混んでいると、macOS は、入りきらないアイコンを、何も言わずに隠します。Cooltime が出てこないときは、「せまくする」をオンに。Command キーを押しながらドラッグすると、位置も動かせます。")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }
}

/// キャラクターの1行。選んだ・外した行だけが描き直されるよう、別の部品にしてある。
private struct CharacterRow: View {
    let id: String
    let selected: Bool
    private static let states: [(CharacterState, String)] = [(.ok, "制限なし"), (.limit, "制限中"), (.fail, "取得に失敗")]

    var body: some View {
        HStack(spacing: 16) {
            Text(CharacterData.names[id] ?? id).frame(width: 64, alignment: .leading)
            ForEach(Self.states, id: \.0) { state, label in
                VStack(spacing: 4) {
                    Image(nsImage: CharacterRenderer.image(id: id, state: state, time: 0, points: 40))
                        .renderingMode(.template)
                        .frame(width: 40, height: 40)
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 72)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.12) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: selected ? 2 : 1))
        // 枠の中のどこを押しても反応するように、押せる範囲を枠全体にする
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: 表示

@MainActor
private struct DisplayGroup: View {
    @AppStorage(ResetTimeStyle.key) private var timeStyle = ResetTimeStyle.absolute.rawValue

    var body: some View {
        SettingsBox(title: "表示", systemImage: "clock") {
            VStack(alignment: .leading, spacing: 8) {
                SubTitle("リセットの書き方")
                Picker("リセットの書き方", selection: $timeStyle) {
                    ForEach(ResetTimeStyle.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 280)
                let sample = Date().addingTimeInterval(4 * 3600 + 12 * 60)
                Text("例: 残り87% · \((ResetTimeStyle(rawValue: timeStyle) ?? .absolute).text(for: sample, now: Date()))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

// MARK: iPhone への通知

@MainActor
private struct NotifyGroup: View {
    @AppStorage(IMessageNotifier.enabledKey) private var notifyEnabled = true
    @AppStorage(IMessageNotifier.handleKey) private var notifyHandle = ""
    @AppStorage(RemindersSync.enabledKey) private var remindersEnabled = false
    @State private var notifyResult: String?
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsBox(title: "iPhone への通知", systemImage: "bell") {
            VStack(alignment: .leading, spacing: 8) {
                SubTitle("iMessage（自分宛て）")
                Toggle("制限が解けたとき・クレジットが増えたとき、知らせる", isOn: $notifyEnabled)
                TextField("自分の電話番号（+81…）か Apple ID のメールアドレス", text: $notifyHandle)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                HStack {
                    Button("テスト送信") {
                        notifyResult = "送っています…"
                        Task {
                            do {
                                try await IMessageNotifier.send("Cooltime のテストです", to: notifyHandle)
                                notifyResult = "送りました。iPhone に届いたか、確かめてください。"
                            } catch { notifyResult = error.localizedDescription }
                        }
                    }
                    .disabled(notifyHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let notifyResult { Text(notifyResult).font(.caption).foregroundStyle(.secondary) }
                }
                Note("Mac の「メッセージ」に iMessage でサインインしている必要があります。初めて送るとき、操作の許可を聞かれます。Mac がスリープ中は、起きたときにまとめて知らせます。文面に、APIキーや数字は入りません。")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SubTitle("リマインダー")
                Toggle("制限が解ける時刻に、iPhone のリマインダーで知らせる", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, on in
                        guard on else { return }
                        Task {
                            if await RemindersSync.requestAccess() { model.publishStatusPage(force: true) }
                            else { model.reminderError = "リマインダーへのアクセスが許可されていません。システム設定 → プライバシーとセキュリティ → リマインダー で、Cooltime を許可してください。" }
                        }
                    }
                if remindersEnabled, let e = model.reminderError { Label(e, systemImage: "exclamationmark.triangle").font(.callout) }
                Note("リマインダーに「Cooltime」リストを作り、制限が解ける時刻の項目を置きます。iPhone が、その時刻に通知を鳴らします（Mac が寝ていても届きます）。ウィジェットは、リストで「Cooltime」を選びます。期限を過ぎた項目は「もう使える」の印として残るので、使い終わったらチェックを付けて消してください。")
            }
        }
    }
}

// MARK: スマホで見る

@MainActor
private struct PhoneGroup: View {
    @AppStorage(StatusPageWriter.enabledKey) private var pageEnabled = false
    @AppStorage(StatusPageWriter.widgetKey) private var widgetEnabled = false
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsBox(title: "スマホで見る", systemImage: "iphone") {
            VStack(alignment: .leading, spacing: 8) {
                SubTitle("iCloud Drive のページ")
                Toggle("残りと戻る時刻の一覧を、iCloud Drive に書き出す", isOn: $pageEnabled)
                    .onChange(of: pageEnabled) { _, on in if on { model.publishStatusPage(force: true) } }
                Note("iPhone の「ファイル」アプリ → iCloud Drive → Cooltime → index.html で開けます。Mac が起きている間、1分おきに更新します。")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SubTitle("ウィジェット（Scriptable）")
                Toggle("ウィジェット用のデータを書き出す", isOn: $widgetEnabled)
                    .onChange(of: widgetEnabled) { _, on in if on { model.publishStatusPage(force: true) } }
                Note("iPhone に、無料の Scriptable アプリを入れ、iCloud をオンにして一度開きます。ホーム画面 → ＋ → Scriptable → 編集 → Script で「Cooltime」を選びます。ウィジェットは、OS が5〜15分おきに読み直します。")
            }

            if (pageEnabled || widgetEnabled), let e = model.pageError {
                Label(e, systemImage: "exclamationmark.triangle").font(.callout)
            }
            Note("書くのは、サービス名・残り・戻る時刻だけです。APIキーは書きません。外のサービスは使いません。")
        }
    }
}

// MARK: アプリ

@MainActor
private struct AppGroup: View {
    @EnvironmentObject private var updater: Updater

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let v = info?["CFBundleShortVersionString"] as? String else { return "開発版" }
        let b = info?["CFBundleVersion"] as? String
        return "Cooltime \(v)" + (b.map { $0 == v ? "" : " (\($0))" } ?? "")
    }

    var body: some View {
        SettingsBox(title: "アプリ", systemImage: "app.badge") {
            LabeledContent("バージョン") { Text(versionText).textSelection(.enabled) }
            if updater.canUpdate {
                HStack(spacing: 10) {
                    switch updater.state {
                    case .idle, .upToDate, .failed:
                        Button("更新を確認") { Task { await updater.check() } }
                        switch updater.state {
                        case .upToDate: Text("最新です").font(.caption).foregroundStyle(.secondary)
                        case .failed(let m): Text(m).font(.caption).foregroundStyle(.red)
                        default: EmptyView()
                        }
                    case .checking:
                        Text("確認中…").font(.caption).foregroundStyle(.secondary)
                    case .available(let v):
                        Button("\(v) に更新して再起動") { Task { await updater.install() } }
                    case .installing:
                        Text("入れ替え中…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Note("更新の確認も、入れ替えも、ボタンを押したときだけ通信します。")
            }
        }
    }
}
