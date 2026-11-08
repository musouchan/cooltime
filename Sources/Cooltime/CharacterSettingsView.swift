import SwiftUI
import AppKit
import CooltimeCore

/// 管理画面の「キャラクター」: 5種類から選ぶ。動きの設定。
@MainActor
struct CharacterSettingsView: View {
    @AppStorage(CharacterPrefs.characterKey) private var characterID = "bunny"
    @AppStorage(CharacterPrefs.motionKey) private var motion = MotionSetting.full.rawValue
    @AppStorage(CharacterPrefs.lowPowerKey) private var inLowPower = false
    @AppStorage(ResetTimeStyle.key) private var timeStyle = ResetTimeStyle.absolute.rawValue
    @AppStorage(DisplayStyle.key) private var displayStyle = DisplayStyle.simple.rawValue
    @AppStorage(CharacterPrefs.compactKey) private var compact = false
    @AppStorage(CharacterPrefs.backgroundKey) private var background = true
    @AppStorage(IMessageNotifier.enabledKey) private var notifyEnabled = true
    @AppStorage(IMessageNotifier.handleKey) private var notifyHandle = ""
    @State private var notifyResult: String?
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

    private let states: [(CharacterState, String)] = [(.ok, "制限なし"), (.limit, "制限中"), (.fail, "取得に失敗")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("リセットの書き方").font(.title3).fontWeight(.semibold)
                    Picker("リセットの書き方", selection: $timeStyle) {
                        ForEach(ResetTimeStyle.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 280)
                    let sample = Date().addingTimeInterval(4 * 3600 + 12 * 60)
                    Text("例: 残り87% · \((ResetTimeStyle(rawValue: timeStyle) ?? .absolute).text(for: sample, now: Date()))")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("グラフの見た目").font(.title3).fontWeight(.semibold)
                    Picker("グラフの見た目", selection: $displayStyle) {
                        ForEach(DisplayStyle.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 280)
                    Text("残りの棒と、振り返りのグラフが変わります。メニューバーは、いつもシンプルです。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("メニューバーの見た目").font(.title3).fontWeight(.semibold)
                    Toggle("うすい丸い背景を付ける（他のアイコンと見分けやすくなります）", isOn: $background)
                    Toggle("せまくする（サービスのアイコンなし・短い文字）", isOn: $compact)
                    Text("メニューバーが混んでいると、macOS は、入りきらないアイコンを、何も言わずに隠します。Cooltime が出てこないときに、オンにしてください。Command キーを押しながら、アイコンをドラッグすると、位置も動かせます。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("戻ったときの通知").font(.title3).fontWeight(.semibold)
                    Toggle("制限が解けたとき・クレジットが増えたとき、自分宛ての iMessage で知らせる", isOn: $notifyEnabled)
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
                    Text("Mac の「メッセージ」に、iMessage でサインインしている必要があります。初めて送るときに、Cooltime が「メッセージ」を操作してよいか聞かれるので、許可してください。Mac がスリープ中は確認できないので、起きたときに、まとめて知らせます。送る文面は「○○が使えるようになりました」だけで、APIキーや数字は送りません。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                PhoneSettingsSection()

                Divider()

                Text("メニューバーのキャラクター").font(.title3).fontWeight(.semibold)
                Text("状態は、色ではなく、耳の形・記号（z と ×）・動きで見分けられます。").font(.callout).foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(CharacterData.ids, id: \.self) { id in
                        Button { characterID = id } label: { row(id) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(CharacterData.names[id] ?? id)
                            .accessibilityAddTraits(characterID == id ? [.isSelected] : [])
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("動き").font(.caption).foregroundStyle(.secondary)
                    Picker("動き", selection: $motion) {
                        ForEach(MotionSetting.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                    Toggle("低電力モードのときも動かす", isOn: $inLowPower)
                    Text("「ときどきだけ」は、制限なしのときのまばたきだけ。「視差効果を減らす」がオンのとき、画面がスリープしているときは、自動で止まります。低電力モードのときは、既定ではまばたきだけです（上のスイッチで、動かせます。電池の減りが、少し早くなることがあります）。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let reason { Label(reason, systemImage: "info.circle").font(.callout).padding(.top, 4) }
                }
            }
            .padding(20)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }

    private func row(_ id: String) -> some View {
        let selected = characterID == id
        return HStack(spacing: 16) {
            Text(CharacterData.names[id] ?? id).frame(width: 64, alignment: .leading)
            ForEach(states, id: \.0) { state, label in
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
    }
}


/// 「スマホで見る」。モデルの変化（20秒ごと）で、キャラクターの一覧まで描き直さないよう、別の部品にしてある。
@MainActor
private struct PhoneSettingsSection: View {
    @AppStorage(StatusPageWriter.enabledKey) private var pageEnabled = false
    @AppStorage(StatusPageWriter.widgetKey) private var widgetEnabled = false
    @EnvironmentObject private var model: AppModel

    var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("スマホで見る").font(.title3).fontWeight(.semibold)
                Toggle("残りと戻る時刻の一覧を、iCloud Drive に書き出す", isOn: $pageEnabled)
                    .onChange(of: pageEnabled) { _, on in if on { model.publishStatusPage(force: true) } }
                Toggle("iPhone のウィジェット（Scriptable）用のデータを書き出す", isOn: $widgetEnabled)
                    .onChange(of: widgetEnabled) { _, on in if on { model.publishStatusPage(force: true) } }
                Text("iPhone に、無料の Scriptable アプリを入れて、iCloud をオンにして一度開いてください。そのあと、ホーム画面を長押し → ＋ → Scriptable → ウィジェットを追加 → 長押しして編集 → Script で「Cooltime」を選びます（Cooltime.js は、自動で置かれます）。ウィジェットは、OS が5〜15分おきに読み直すので、Mac のメニューバーより遅れます。上に「○時○分 時点」と出します。")
                    .font(.caption).foregroundStyle(.secondary)
                if (pageEnabled || widgetEnabled), let e = model.pageError { Label(e, systemImage: "exclamationmark.triangle").font(.callout) }
                Text("iPhone の「ファイル」アプリ → iCloud Drive → 「Cooltime」→ index.html で開けます（共有ボタンから「ホーム画面に追加」もできます）。Mac が起きている間だけ、1分おきに更新されます。ページには、残り・戻る時刻・サービス名だけを書き、APIキーは書きません。外のサービスは使いません。初めて書くとき、フォルダへのアクセスの許可を聞かれることがあります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
    }
}
