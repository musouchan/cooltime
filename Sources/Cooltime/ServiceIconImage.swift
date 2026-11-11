import AppKit
import CooltimeCore

/// メニューバーに添える、サービスのアイコン。
/// ロゴ画像は同梱しない。インストール済みのアプリのアイコンを借りるか、サービス名の頭文字で出す。
@MainActor
enum ServiceIconImage {
    private static var cache: [String: NSImage] = [:]

    static func image(for service: ServiceDef, points: CGFloat) -> NSImage {
        let key = "\(service.id)|\(Int(points))"
        if let hit = cache[key] { return hit }
        let image = appIcon(service, points) ?? savedLogo(service, points) ?? letterBadge(service, points)
        cache[key] = image
        return image
    }

    static func reset() { cache.removeAll() }

    private static func savedLogo(_ service: ServiceDef, _ points: CGFloat) -> NSImage? {
        guard let logo = ServiceIconStore.cached(service.id) else { return nil }
        let radius = ServiceIconStore.cornerRadius(for: points)
        return NSImage(size: NSSize(width: points, height: points), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            logo.draw(in: rect)
            return true
        }
    }

    private static func appIcon(_ service: ServiceDef, _ points: CGFloat) -> NSImage? {
        for id in service.appBundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                  let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage else { continue }
            icon.size = NSSize(width: points, height: points)
            return icon
        }
        return nil
    }

    /// アプリが無いもの（API など）は、灰色の角丸に、名前の頭文字。
    private static func letterBadge(_ service: ServiceDef, _ points: CGFloat) -> NSImage {
        let letter = String(service.name.prefix(1)) as NSString
        return NSImage(size: NSSize(width: points, height: points), flipped: false) { rect in
            ServiceIconStore.badgeColor(service.id).setFill()
            NSBezierPath(roundedRect: rect, xRadius: ServiceIconStore.cornerRadius(for: points), yRadius: ServiceIconStore.cornerRadius(for: points)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: points * 0.62, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let size = letter.size(withAttributes: attrs)
            letter.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2), withAttributes: attrs)
            return true
        }
    }
}
