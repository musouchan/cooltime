import Foundation

public enum BrowserbaseUsage {
    private struct ProjectUsage: Decodable {
        let browserMinutes: Int64
        let proxyBytes: Int64
    }

    public static func configuration(from input: String) throws -> (url: String, apiKey: String) {
        let fields = input.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 2 else { throw ParseError.unsupported("プロジェクトID|APIキー の形式で入力してください") }
        let project = fields[0].trimmingCharacters(in: .whitespaces)
        let key = fields[1].trimmingCharacters(in: .whitespaces)
        guard !project.isEmpty,
              project.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
              !key.isEmpty, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ParseError.unsupported("BrowserbaseのプロジェクトIDとAPIキーを確認してください")
        }
        return ("https://api.browserbase.com/v1/projects/\(project)/usage", key)
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let exactCount: ClosedRange<Int64> = 0...9_007_199_254_740_991
        guard let usage = try? JSONDecoder().decode(ProjectUsage.self, from: data),
              exactCount.contains(usage.browserMinutes), exactCount.contains(usage.proxyBytes) else {
            throw ParseError.unsupported("Browserbaseの利用実績を読み取れません")
        }
        return Snapshot(windows: [
            UsageWindow(label: "ブラウザー利用", reportedAmount: Double(usage.browserMinutes), reportedUnit: "分"),
            UsageWindow(label: "プロキシ転送量", reportedAmount: Double(usage.proxyBytes), reportedUnit: "B"),
        ], fetchedAt: fetchedAt)
    }
}
