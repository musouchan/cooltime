import SwiftUI
import AppKit
import CooltimeCore

/// カタログ内の全サービスに、同梱アイコンを表示する。
struct AppIconView: View {
    let service: ServiceDef
    var size: CGFloat = 22

    var body: some View {
        Image(nsImage: ServiceIconImage.image(for: service, points: size))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
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
