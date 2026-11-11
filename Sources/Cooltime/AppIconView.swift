import SwiftUI
import AppKit
import CooltimeCore

/// ロゴ画像は同梱しない。インストール済みのアプリのアイコン → 取得して保存したロゴ → 色つきの頭文字、の順で出す。
struct AppIconView: View {
    let service: ServiceDef
    var size: CGFloat = 22
    @State private var tick = 0

    private var icons: [NSImage] {
        service.appBundleIDs.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
    }

    var body: some View {
        let found = icons
        let saved = found.isEmpty ? ServiceIconStore.cached(service.id) : nil
        Group {
            if let saved {
                Image(nsImage: saved).resizable().frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: ServiceIconStore.cornerRadius(for: size), style: .continuous))
            } else if found.isEmpty {
                // アプリもロゴも無いもの（API など）は、色つきの頭文字で出す。
                Text(String(service.name.prefix(1)))
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: ServiceIconStore.cornerRadius(for: size), style: .continuous)
                        .fill(Color(nsColor: ServiceIconStore.badgeColor(service.id))))
            } else {
                // 1つの枠を共有する複数のアプリは、アイコンを重ねる。
                HStack(spacing: -size * 0.45) {
                    ForEach(Array(found.enumerated()), id: \.offset) { _, img in
                        Image(nsImage: img).resizable().frame(width: size, height: size)
                    }
                }
            }
        }
        .accessibilityHidden(true)
        .id(tick)
        .onReceive(NotificationCenter.default.publisher(for: ServiceIconStore.changed)) { _ in tick += 1 }
    }
}

/// 状態は色だけに頼らず、形でも分かるようにする。
struct StateGlyph: View {
    let state: QuotaState
    var body: some View {
        switch state {
        case .limited: Image(systemName: "pause.circle").foregroundStyle(.red)
        case .available: Image(systemName: "checkmark.circle").foregroundStyle(.green)
        case .stale: Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        case .unset: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}

func stateWord(_ state: QuotaState) -> String {
    switch state {
    case .limited: return "制限中"
    case .available: return "使用可能"
    case .stale: return "目安を過ぎた"
    case .unset: return "未設定"
    }
}
