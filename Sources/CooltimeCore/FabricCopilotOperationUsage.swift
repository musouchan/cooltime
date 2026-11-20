import Foundation
import CoreFoundation

/// Reads authorized Fabric capacity operation events saved as JSONL.
/// Reports observed Copilot CU consumption across the capacity, not a Power BI-only quota.
public enum FabricCopilotOperationUsage {
    private static let maximumBytes = 8 * 1_024 * 1_024

    public static func read(path: String) throws -> Snapshot {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), !path.contains("\0"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber, size.intValue <= maximumBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { throw invalid() }
        return try parse(data, fetchedAt: Date())
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else { throw invalid() }
        var seen = Set<String>()
        var total = 0.0
        var powerBIItemsTotal = 0.0
        var count = 0
        var powerBIItemsCount = 0
        for line in text.split(whereSeparator: \.isNewline) {
            guard let bytes = String(line).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  event["type"] as? String == "Microsoft.Fabric.CapacityOperationEvents.Operation",
                  let id = event["id"] as? String, !id.isEmpty, id.utf8.count <= 128,
                  let payload = event["data"] as? [String: Any],
                  let name = payload["operationName"] as? String,
                  let release = payload["releaseType"] as? String else { throw invalid() }
            guard name == "Copilot in Fabric", release == "Public" else { continue }
            guard let cuMs = number(payload["capacityUnitMs"]) else { throw invalid() }
            if seen.insert(id).inserted {
                total += cuMs / 1_000
                count += 1
                if let kind = payload["itemKind"] as? String,
                   kind == "Report" || kind == "SemanticModel" {
                    powerBIItemsTotal += cuMs / 1_000
                    powerBIItemsCount += 1
                }
            }
            guard total.isFinite, total <= 9_007_199_254_740_991,
                  powerBIItemsTotal.isFinite, powerBIItemsTotal <= 9_007_199_254_740_991 else { throw invalid() }
        }
        guard count > 0 else { throw invalid() }
        var windows = [UsageWindow(label: "Copilot in Fabric・記録済み全ワークロード",
                                   reportedAmount: total, reportedUnit: "CU秒")]
        if powerBIItemsCount > 0 {
            windows.append(UsageWindow(label: "Copilot・Power BI関連アイテムのみ（部分値）",
                                       reportedAmount: powerBIItemsTotal, reportedUnit: "CU秒"))
        }
        return Snapshot(windows: windows, fetchedAt: fetchedAt)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let v = n.doubleValue
        return v.isFinite && v >= 0 && v <= 9_007_199_254_740_991 ? v : nil
    }

    private static func invalid() -> ParseError {
        .unsupported("Fabric容量操作イベントからCopilotのCU実績を確認できません")
    }
}
