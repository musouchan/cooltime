import SwiftUI
import AppKit
import CooltimeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock にアイコンは出さない。
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct CooltimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Cooltime 管理", id: "manage") {
            ManageView().environmentObject(model)
        }
        .defaultSize(width: 860, height: 560)
    }
}
