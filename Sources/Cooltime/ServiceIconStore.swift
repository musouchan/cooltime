import AppKit
import CooltimeCore

/// サービスのロゴ。インストール済みのアプリが無いものは、各サービス自身のサイトから、ボタンを押したときだけ取って、この Mac に保存する。
/// ロゴ画像は、このアプリにも、リポジトリにも含めない（各社の商標・著作物のため）。
@MainActor
enum ServiceIconStore {
    static let changed = Notification.Name("cooltime.serviceIconsChanged")
    private static var memory: [String: NSImage] = [:]
    private static var dir: URL { Paths.dir.appendingPathComponent("icons", isDirectory: true) }

    static func cached(_ id: String) -> NSImage? {
        if let m = memory[id] { return m }
        guard let img = NSImage(contentsOf: dir.appendingPathComponent("\(id).png")) else { return nil }
        memory[id] = img
        return img
    }

    /// インストール済みのアプリのアイコンがあるか。
    static func hasAppIcon(_ s: ServiceDef) -> Bool {
        s.bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// まだロゴが無いもの（アプリも、保存したロゴも無い）。
    static func missing(_ services: [ServiceDef]) -> [ServiceDef] {
        services.filter { !hasAppIcon($0) && cached($0.id) == nil && !$0.iconCandidates.isEmpty }
    }

    /// 1つ取る。取れたら true。
    static func fetch(_ s: ServiceDef) async -> Bool {
        for url in s.iconCandidates {
            guard let data = await download(url), let png = normalizedPNG(data) else { continue }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard (try? png.write(to: dir.appendingPathComponent("\(s.id).png"), options: .atomic)) != nil else { continue }
            memory[s.id] = NSImage(data: png)
            NotificationCenter.default.post(name: changed, object: nil)
            return true
        }
        return false
    }

    private static func download(_ url: URL) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Cooltime", forHTTPHeaderField: "User-Agent")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        guard let (data, res) = try? await URLSession(configuration: cfg).data(for: req),
              (res as? HTTPURLResponse)?.statusCode == 200, data.count > 100, data.count < 2_000_000 else { return nil }
        return data
    }

    /// 128px の角丸の PNG にそろえる。画像として読めないもの（HTML など）や、小さすぎるものは捨てる。
    private static func normalizedPNG(_ data: Data) -> Data? {
        guard let src = NSImage(data: data), src.size.width >= 16, src.size.height >= 16 else { return nil }
        let px = 128
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        let rect = NSRect(x: 0, y: 0, width: px, height: px)
        NSColor.white.setFill()
        let clip = NSBezierPath(roundedRect: rect, xRadius: CGFloat(px) * 0.22, yRadius: CGFloat(px) * 0.22)
        clip.fill()
        clip.addClip()
        src.draw(in: rect.insetBy(dx: 8, dy: 8), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// ロゴもアプリも無いときの、色つきの頭文字。色は、サービスごとに決まる（文字との差が大きい、濃い色）。
    static func badgeColor(_ id: String) -> NSColor {
        var h: UInt32 = 5381
        for u in id.unicodeScalars { h = h &* 33 &+ u.value }
        return NSColor(hue: CGFloat(h % 360) / 360, saturation: 0.55, brightness: 0.45, alpha: 1)
    }
}
