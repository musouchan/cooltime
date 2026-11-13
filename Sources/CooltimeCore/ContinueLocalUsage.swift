import Foundation
import CoreFoundation

/// Reads the official Continue CLI session files without starting the CLI or sending a request.
public enum ContinueLocalUsage {
    private static let maximumFiles = 2_000
    private static let maximumFileBytes = 8 * 1_024 * 1_024

    public static func read(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".continue/sessions", isDirectory: true)) throws -> Snapshot {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                             options: [.skipsHiddenFiles]),
              files.count <= maximumFiles else { throw invalid() }
        var sessions: [Data] = []
        for file in files where file.pathExtension == "json" && file.lastPathComponent != "sessions.json" {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize, size <= maximumFileBytes,
                  let data = try? Data(contentsOf: file) else { continue }
            sessions.append(data)
        }
        return try parse(sessions, fetchedAt: Date())
    }

    public static func parse(_ sessions: [Data], fetchedAt: Date) throws -> Snapshot {
        guard !sessions.isEmpty, sessions.count <= maximumFiles else { throw invalid() }
        var prompt = 0.0, completion = 0.0, cost = 0.0
        var count = 0
        for data in sessions {
            guard data.count <= maximumFileBytes,
                  let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw invalid() }
            guard let usage = session["usage"] as? [String: Any] else { continue } // Legacy session.
            guard let p = number(usage["promptTokens"]),
                  let c = number(usage["completionTokens"]),
                  let amount = number(usage["totalCost"]) else { throw invalid() }
            prompt += p
            completion += c
            cost += amount
            count += 1
            guard prompt.isFinite, completion.isFinite, cost.isFinite else { throw invalid() }
        }
        guard count > 0 else { throw invalid() }
        return Snapshot(windows: [
            UsageWindow(label: "Continue入力（保存セッション）", reportedAmount: prompt, reportedUnit: "tokens"),
            UsageWindow(label: "Continue出力（保存セッション）", reportedAmount: completion, reportedUnit: "tokens"),
            UsageWindow(label: "Continue推定費用（保存セッション）", reportedAmount: cost, reportedUnit: "USD")
        ], fetchedAt: fetchedAt)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let v = n.doubleValue
        return v.isFinite && v >= 0 && v <= 9_007_199_254_740_991 ? v : nil
    }

    private static func invalid() -> ParseError {
        .unsupported("Continue CLIの保存済みセッションから利用実績を確認できません")
    }
}
