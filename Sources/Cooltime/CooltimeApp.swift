import SwiftUI
import AppKit
import CooltimeCore

/// ウィンドウを開く操作を、画面（SwiftUI）から呼べるようにする入れ物。
@MainActor
final class AppActions: ObservableObject {
    var openManage: () -> Void = {}
    var openReview: () -> Void = {}
}

/// 管理と振り返りのウィンドウ。メニューバーのアイコンを `NSStatusItem` で出すので、
/// ウィンドウも AppKit 側で持つ。
@MainActor
final class WindowsController {
    private let model: AppModel
    private let updater: Updater
    private let actions: AppActions
    private var manage: NSWindow?
    private var review: NSWindow?

    init(model: AppModel, updater: Updater, actions: AppActions) {
        self.model = model
        self.updater = updater
        self.actions = actions
    }

    func showManage() {
        if manage == nil {
            manage = makeWindow(title: "Cooltime 管理", size: NSSize(width: 860, height: 560),
                                content: AnyView(ManageView().environmentObject(model).environmentObject(updater).environmentObject(actions)))
        }
        present(manage)
    }

    func showReview() {
        if review == nil {
            review = makeWindow(title: "Cooltime 振り返り", size: NSSize(width: 760, height: 620),
                                content: AnyView(ReviewView().environmentObject(model)))
        }
        present(review)
    }

    private func makeWindow(title: String, size: NSSize, content: AnyView) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title
        w.contentViewController = NSHostingController(rootView: content)
        w.setContentSize(size)
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var updater: Updater?
    private var status: StatusItemController?
    private var windows: WindowsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock にアイコンは出さない。
        NSApp.setActivationPolicy(.accessory)

        let model = AppModel()
        let updater = Updater()
        let actions = AppActions()
        let status = StatusItemController(model: model, actions: actions)
        let windows = WindowsController(model: model, updater: updater, actions: actions)
        actions.openManage = { [weak status, weak windows] in status?.closePopover(); windows?.showManage() }
        actions.openReview = { [weak status, weak windows] in status?.closePopover(); windows?.showReview() }

        self.model = model
        self.updater = updater
        self.status = status
        self.windows = windows
    }

    /// もう一度アプリを開いたとき（Finder でのダブルクリック、`open` など）は、管理画面を開く。
    /// メニューバーが混んでアイコンが隠れていても、設定にたどり着けるようにするため。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows?.showManage()
        return true
    }
}

@main
struct CooltimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // 画面は、すべて AppKit 側（AppDelegate）で持つ。SwiftUI のシーンは、空のまま。
    var body: some Scene {
        Settings { EmptyView() }
    }
}
