import SwiftUI
import AppKit
import CooltimeCore

/// 管理画面の「キャラクター」: 5種類から選ぶ。動きの設定。
@MainActor
struct CharacterSettingsView: View {
    @AppStorage(CharacterPrefs.characterKey) private var characterID = "bunny"
    @AppStorage(CharacterPrefs.motionKey) private var motion = MotionSetting.full.rawValue
    @AppStorage(CharacterPrefs.lowPowerKey) private var inLowPower = false
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
