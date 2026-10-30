import SwiftUI
import AppKit

@main
struct CooltimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            MenuLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("管理", id: "manager") {
            ManagerView(store: store)
                .frame(minWidth: 760, minHeight: 520)
        }
    }
}

/// Dock にアイコンを出さない（メニューバーだけに常駐する）。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuLabel: View {
    @ObservedObject var store: Store

    var body: some View {
        // 制限中が無いとき・復旧目安を過ぎたときは、このアプリのアイコンだけ。
        if let text = store.menuText {
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                Text(text).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("利用制限が戻るまで \(text)")
        } else {
            Image(systemName: "hourglass")
                .accessibilityLabel("利用上限の確認")
        }
    }
}
