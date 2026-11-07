import AppKit
import Combine
import SwiftUI
import CooltimeCore

/// メニューバーのキャラクターと数字。`NSStatusItem` で出す
/// （`MenuBarExtra` のラベルは、動きが安定しないことがあるため）。
///
/// 電池への配慮:
///  - 画面の書き換えは 1 秒に 8 コマまで。コマごとの画像は使い回す。
///  - 画面がスリープ／メニューバーが隠れているときは、タイマーごと止める。
///  - 「低電力モード」では、まばたきだけ（それ以外は静止）。管理画面で、低電力モードでも動かすことを選べる。
///  - 「視差効果を減らす」では、静止。
///  - 管理画面の設定: 動く／ときどきだけ／止める。
@MainActor
final class StatusItemController: NSObject {
    private enum Mode { case still, blink, full }

    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var screenAsleep = false
    private var display: MenuBarDisplay = .failed
    private var lastTitle: String?
    private var lastImageKey = ""

    init(model: AppModel, actions: AppActions) {
        self.model = model
        super.init()

        let host = NSHostingController(rootView: PopoverView().environmentObject(model).environmentObject(actions))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient

        // 場所を、macOS に覚えさせる（Command を押しながらドラッグして、好きな位置に動かせる）
        item.autosaveName = "app.cooltime.statusitem"
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
        }

        // モデルの変化（数字・状態）と、設定の変更で、表示を直す
        model.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)

        // 動かしてよいかが変わる出来事
        let ws = NSWorkspace.shared.notificationCenter
        ws.publisher(for: NSWorkspace.screensDidSleepNotification).sink { [weak self] _ in self?.screenAsleep = true; self?.updateTimer() }.store(in: &cancellables)
        ws.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in self?.screenAsleep = true; self?.updateTimer() }.store(in: &cancellables)
        ws.publisher(for: NSWorkspace.screensDidWakeNotification).sink { [weak self] _ in self?.screenAsleep = false; self?.updateTimer() }.store(in: &cancellables)
        ws.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in self?.screenAsleep = false; self?.updateTimer() }.store(in: &cancellables)
        ws.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification).sink { [weak self] _ in self?.updateTimer() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).sink { [weak self] _ in self?.updateTimer() }.store(in: &cancellables)
        if let window = item.button?.window {
            NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: window)
                .sink { [weak self] _ in self?.updateTimer() }.store(in: &cancellables)
        }

        refresh()
    }

    // MARK: ポップオーバー

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() { popover.performClose(nil) }

    // MARK: 表示

    /// 丸い背景。壁紙で透けて見づらくならないよう、背景に加えて、はっきりした枠線も付ける
    /// （色は、文字と同じ labelColor から作るので、ライト・ダークのどちらでも、文字と同じだけ目立つ）。
    /// 「コントラストを上げる」がオンのときは、さらに濃くする。角は、いちばん丸く（高さの半分）。
    private func applyBackground(to button: NSStatusBarButton) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        guard CharacterPrefs.menuBarBackground else {
            layer.backgroundColor = nil
            layer.borderWidth = 0
            return
        }
        let high = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        var fill = NSColor.labelColor.withAlphaComponent(high ? 0.30 : 0.20).cgColor
        var line = NSColor.labelColor.withAlphaComponent(high ? 0.95 : 0.65).cgColor
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            fill = NSColor.labelColor.withAlphaComponent(high ? 0.30 : 0.20).cgColor
            line = NSColor.labelColor.withAlphaComponent(high ? 0.95 : 0.65).cgColor
        }
        layer.backgroundColor = fill
        layer.borderColor = line
        layer.borderWidth = high ? 1.5 : 1
        layer.cornerRadius = 999   // 高さの半分に丸められる（完全なカプセル形）
        layer.cornerCurve = .circular
    }

    private func refresh() {
        guard let button = item.button else { return }
        display = model.menuBarDisplay
        let compact = CharacterPrefs.menuBarCompact
        let text = display.text(now: model.now, compact: compact)

        // 数字と、その数字のもとのサービス（アイコン）が変わったときだけ、タイトルを作り直す
        // せまい表示では、サービスのアイコンを付けない
        let service = compact ? nil : display.source.flatMap { Catalog.service($0) }
        let titleKey = "\(text ?? "")|\(service?.id ?? "")"
        if titleKey != lastTitle {
            lastTitle = titleKey
            if let text {
                let title = NSMutableAttributedString(string: " ")
                if let service {
                    // サービスのアプリのアイコン（色つき）を、数字の前に添える
                    let attachment = NSTextAttachment()
                    attachment.image = ServiceIconImage.image(for: service, points: 14)
                    attachment.bounds = CGRect(x: 0, y: -3, width: 14, height: 14)
                    title.append(NSAttributedString(attachment: attachment))
                    title.append(NSAttributedString(string: " "))
                }
                title.append(NSAttributedString(string: text + " ", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                ]))
                button.attributedTitle = title
                button.imagePosition = .imageLeading
            } else {
                button.attributedTitle = NSAttributedString(string: "")
                button.imagePosition = .imageOnly
            }
        }
        applyBackground(to: button)
        button.toolTip = model.menuBarTooltip
        button.setAccessibilityLabel("Cooltime: " + (service.map { "\($0.name) " } ?? "") + (text ?? "取得できていません"))
        updateImage(force: true)
        updateTimer()
    }

    private func mode() -> Mode {
        let visible = item.button?.window?.occlusionState.contains(.visible) ?? false
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || screenAsleep || !visible { return .still }
        let blinkOnly: Mode = display.characterState == .ok ? .blink : .still
        switch CharacterPrefs.motion {
        case .still: return .still
        case .sometimes: return blinkOnly
        case .full:
            let saving = ProcessInfo.processInfo.isLowPowerModeEnabled && !CharacterPrefs.motionInLowPower
            return saving ? blinkOnly : .full
        }
    }

    private func updateTimer() {
        let m = mode()
        if m == .still {
            timer?.invalidate()
            timer = nil
            updateImage(force: true)
        } else if timer == nil {
            let t = Timer(timeInterval: 1 / CharacterRenderer.fps, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateImage(force: false) }
            }
            t.tolerance = 0.03
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func updateImage(force: Bool) {
        guard let button = item.button else { return }
        let m = mode()
        let state = display.characterState
        let id = CharacterPrefs.characterID

        var time = m == .still ? 0 : Date.timeIntervalSinceReferenceDate
        var only: Set<String>?
        if m == .blink {
            only = ["eyes"]
            // まばたきをしていない間は、同じ画像のまま（描き直さない）
            if CharacterRenderer.motion.transform(state: state, group: "eyes", at: time).scaleY == 1 { time = 0 }
        }
        let key = "\(id)|\(state.rawValue)|\(Int(time * CharacterRenderer.fps))|\(only != nil)"
        guard force || key != lastImageKey else { return }
        lastImageKey = key
        button.image = CharacterRenderer.image(id: id, state: state, time: time, only: only)
    }
}
