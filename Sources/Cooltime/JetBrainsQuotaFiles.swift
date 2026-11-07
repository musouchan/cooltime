import Foundation
import CooltimeCore

enum JetBrainsQuotaFiles {
    struct Located {
        let url: URL
        let modifiedAt: Date
    }

    static func read() throws -> Snapshot {
        guard let located = latest() else { throw FetchError.noFile }
        let values = try located.url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 262_144,
              let data = try? Data(contentsOf: located.url, options: [.mappedIfSafe]) else {
            throw ParseError.unsupported("JetBrains AI Assistantのクォータファイルを読み取れません")
        }
        return try JetBrainsAIQuota.parse(data, fetchedAt: located.modifiedAt)
    }

    static func latest(fileManager: FileManager = .default) -> Located? {
        let support = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let roots = ["JetBrains", "Google"].map { support.appendingPathComponent($0, isDirectory: true) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        var newest: Located?
        for root in roots {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var inspected = 0
            while let url = enumerator.nextObject() as? URL, inspected < 20_000 {
                inspected += 1
                guard url.lastPathComponent == "AIAssistantQuotaManager2.xml",
                      url.deletingLastPathComponent().lastPathComponent == "options",
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, let modified = values.contentModificationDate else { continue }
                if newest == nil || modified > newest!.modifiedAt {
                    newest = Located(url: url, modifiedAt: modified)
                }
            }
        }
        return newest
    }
}
