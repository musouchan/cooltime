import AppKit
import CooltimeCore

/// 同梱されたサービスアイコンを、画面とメニューバーで共有する。
@MainActor
enum ServiceIconImage {
    private static var cache: [String: NSImage] = [:]
    private static let atlas: CGImage? = {
        guard let url = Bundle.module.url(forResource: "ServiceIcons", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }()

    static func image(for service: ServiceDef, points: CGFloat) -> NSImage {
        let key = "\(service.id)|\(Int(points))"
        if let hit = cache[key] { return hit }
        let image = bundledIcon(service, points) ?? appIcon(service, points) ?? letterBadge(service, points)
        cache[key] = image
        return image
    }

    private static func bundledIcon(_ service: ServiceDef, _ points: CGFloat) -> NSImage? {
        guard let index = ServiceIconCatalog.indices[service.id], let atlas else { return nil }
        let side = ServiceIconCatalog.cellSize
        let cell = CGRect(x: CGFloat((index % ServiceIconCatalog.columns) * side),
                          y: CGFloat((index / ServiceIconCatalog.columns) * side),
                          width: CGFloat(side), height: CGFloat(side))
        guard let cropped = atlas.cropping(to: cell) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: points, height: points))
    }

    private static func appIcon(_ service: ServiceDef, _ points: CGFloat) -> NSImage? {
        for id in service.bundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                  let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage else { continue }
            icon.size = NSSize(width: points, height: points)
            return icon
        }
        return nil
    }

    /// 将来追加される未収録サービスの最終フォールバック。
    private static func letterBadge(_ service: ServiceDef, _ points: CGFloat) -> NSImage {
        let letter = String(service.name.prefix(1)) as NSString
        return NSImage(size: NSSize(width: points, height: points), flipped: false) { rect in
            NSColor(white: 0.55, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: points * 0.25, yRadius: points * 0.25).fill()
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
