import Foundation
import CoreFoundation

/// Reads a user-selected JSONL file of Pinecone response usage objects.
/// Each line is a captured response or {"usage":{"read_units":...}} record.
/// No Pinecone request is issued; figures cover only the captured responses.
public enum PineconeLocalUsage {
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
        var read = 0.0, write = 0.0, measured = 0
        var sawRead = false, sawWrite = false
        for line in text.split(whereSeparator: \.isNewline) {
            guard let bytes = String(line).data(using: .utf8),
                  let response = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let usage = response["usage"] as? [String: Any] else { throw invalid() }
            let readUnits = number(usage["read_units"])
            let writeUnits = number(usage["write_units"])
            guard readUnits != nil || writeUnits != nil else { throw invalid() }
            sawRead = sawRead || readUnits != nil
            sawWrite = sawWrite || writeUnits != nil
            read += readUnits ?? 0
            write += writeUnits ?? 0
            measured += 1
            guard read.isFinite, write.isFinite else { throw invalid() }
        }
        guard measured > 0 else { throw invalid() }
        var windows: [UsageWindow] = []
        if sawRead { windows.append(UsageWindow(label: "Pinecone読取（保存応答分）", reportedAmount: read, reportedUnit: "RU")) }
        if sawWrite { windows.append(UsageWindow(label: "Pinecone書込（保存応答分）", reportedAmount: write, reportedUnit: "WU")) }
        return Snapshot(windows: windows, fetchedAt: fetchedAt)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let v = n.doubleValue
        return v.isFinite && v >= 0 && v <= 9_007_199_254_740_991 ? v : nil
    }

    private static func invalid() -> ParseError {
        .unsupported("Pineconeの保存済み応答から利用単位を確認できません")
    }
}
