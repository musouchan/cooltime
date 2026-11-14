import Foundation
import CoreFoundation

/// Reads saved responses from the documented Create Mask API. This is observed
/// usage of the supplied jobs, never the account balance or an inferred quota.
public enum REimagineHomeMaskUsage {
    private static let maximumBytes = 8 * 1_024 * 1_024

    public static func read(path: String) throws -> Snapshot {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), !path.contains("\0"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { throw invalid() }
        return try parse(data, fetchedAt: Date())
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else { throw invalid() }
        var jobs: [String: Double] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let bytes = String(line).data(using: .utf8),
                  let response = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  response["status"] as? String == "success",
                  let payload = response["data"] as? [String: Any],
                  let jobID = payload["job_id"] as? String, !jobID.isEmpty,
                  let consumed = number(payload["credits_consumed"]) else { throw invalid() }
            if let previous = jobs[jobID], previous != consumed { throw invalid() }
            jobs[jobID] = consumed
        }
        guard !jobs.isEmpty else { throw invalid() }
        let total = jobs.values.reduce(0, +)
        guard total.isFinite, total <= 9_007_199_254_740_991 else { throw invalid() }
        return Snapshot(windows: [UsageWindow(label: "Create Mask（記録済みジョブ）",
                                              reportedAmount: total, reportedUnit: "credits")],
                        fetchedAt: fetchedAt)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let v = n.doubleValue
        return v.isFinite && v >= 0 && v <= 9_007_199_254_740_991 ? v : nil
    }

    private static func invalid() -> ParseError {
        .unsupported("REimagineHomeのCreate Mask応答ログから消費クレジットを確認できません")
    }
}
