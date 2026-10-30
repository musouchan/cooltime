import SwiftUI
import AppKit
import CooltimeCore

/// メニューバーには「一番早く戻るもの」だけを、カプセルの中にまとめて出す。
/// カプセルで、他のアプリのアイコンと見分ける。無いときはアプリのアイコンだけ。
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    private var text: String? {
        guard let pick = model.menuBarPick else { return nil }
        let base = formatRemaining(until: pick.until, now: model.now)
        return pick.others > 0 ? "\(base) +\(pick.others)" : base
    }

    var body: some View {
        let spoken = text ?? "Cooltime"
        if let image = render(text) {
            Image(nsImage: image).accessibilityLabel(spoken)
        } else {
            Text(text ?? "Cooltime")
        }
    }

    @MainActor
    private func render(_ text: String?) -> NSImage? {
        let content = HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 11, weight: .semibold))
            if let text { Text(text).font(.system(size: 12, weight: .medium)).monospacedDigit() }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().strokeBorder(Color.black, lineWidth: 1))
        .padding(1)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        // テンプレート画像にして、ライト／ダークの色はシステムに任せる。
        image.isTemplate = true
        return image
    }
}
