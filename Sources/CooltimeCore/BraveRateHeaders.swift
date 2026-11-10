import Foundation

/// Reads response headers from an existing Brave Search API request. Never sends a quota-check request.
public enum BraveRateHeaders {
    public static func read(path: String, now: Date = Date()) throws -> Snapshot {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), !path.contains("\0"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber, size.intValue <= 64 * 1_024,
              let capturedAt = attributes[.modificationDate] as? Date,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { throw invalid() }
        return try parse(data, capturedAt: capturedAt, now: now)
    }

    public static func parse(_ data: Data, capturedAt: Date, now: Date) throws -> Snapshot {
        guard data.count <= 64 * 1_024, let text = String(data: data, encoding: .utf8),
              capturedAt <= now.addingTimeInterval(60) else { throw invalid() }
        var headers: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("HTTP/") { headers.removeAll(); continue }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].lowercased()
            if name.hasPrefix("x-ratelimit-") {
                headers[name] = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        func numbers(_ key: String) -> [Int]? {
            guard let value = headers[key] else { return nil }
            let parts = value.split(separator: ",", omittingEmptySubsequences: false)
            let parsed = parts.map { Int($0.trimmingCharacters(in: .whitespaces)) }
            return parsed.allSatisfy { $0 != nil } ? parsed.compactMap { $0 } : nil
        }
        guard let limits = numbers("x-ratelimit-limit"),
              let remaining = numbers("x-ratelimit-remaining"),
              let reset = numbers("x-ratelimit-reset"),
              let policy = headers["x-ratelimit-policy"]?.split(separator: ",", omittingEmptySubsequences: false),
              !limits.isEmpty, limits.count == remaining.count, limits.count == reset.count,
              limits.count == policy.count else { throw invalid() }
        var windows: [UsageWindow] = []
        for index in limits.indices {
            let parts = policy[index].split(separator: ";")
            guard parts.count == 2,
                  Int(parts[0].trimmingCharacters(in: .whitespaces)) == limits[index],
                  parts[1].trimmingCharacters(in: .whitespaces).hasPrefix("w="),
                  let duration = Int(parts[1].trimmingCharacters(in: .whitespaces).dropFirst(2)),
                  duration > 0, limits[index] >= 0, remaining[index] >= 0,
                  reset[index] >= 0, reset[index] <= duration,
                  (limits[index] == 0 || remaining[index] <= limits[index]) else { throw invalid() }
            // Short-lived burst limits are not a monthly allowance; an unlimited 0 is not zero remaining.
            guard duration >= 86_400, limits[index] > 0 else { continue }
            let expiry = capturedAt.addingTimeInterval(TimeInterval(reset[index]))
            guard expiry > now else { continue }
            let label = duration >= 2_419_200 ? "Brave月間リクエスト枠" : "Brave長期リクエスト枠（\(duration)秒）"
            windows.append(UsageWindow(label: label,
                                       usedPercent: 100 * Double(limits[index] - remaining[index]) / Double(limits[index]),
                                       remainingCount: Double(remaining[index]), resetsAt: expiry))
        }
        guard !windows.isEmpty else { throw invalid() }
        return Snapshot(windows: windows, fetchedAt: capturedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Braveの有効な長期枠ヘッダーを確認できません。既存API応答のヘッダーを保存してください")
    }
}
