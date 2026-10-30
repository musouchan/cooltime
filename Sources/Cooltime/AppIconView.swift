import SwiftUI
import AppKit
import CooltimeCore

/// ロゴ画像は同梱しない。インストール済みのアプリのアイコンを借りるか、サービス名の文字で出す。
struct AppIconView: View {
    let service: ServiceDef
    var size: CGFloat = 22

    private var icons: [NSImage] {
        service.bundleIDs.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
    }

    var body: some View {
        let found = icons
        Group {
            if found.isEmpty {
                // アプリが無いもの（API など）は、名前の頭文字で出す。
                Text(String(service.name.prefix(1)))
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.25).fill(.quaternary))
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
