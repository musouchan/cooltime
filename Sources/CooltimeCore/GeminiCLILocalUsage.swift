import Foundation
import CoreFoundation

/// Reads only numerical Gemini CLI API response events from an explicitly selected telemetry file.
/// The file may also contain prompts, responses and traces; none of these are retained or returned.
public enum GeminiCLILocalUsage {
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
        // The official file exporters append indented JSON objects without a surrounding array.
        // Delimit objects while honoring quoted braces and escapes; skip unrelated logs and spans.
        var depth = 0
        var start: String.Index?
        var quoted = false
        var escaped = false
        var input = 0.0
        var output = 0.0
        var responses = 0
        for index in text.indices {
            let char = text[index]
            if depth == 0 {
                if char.isWhitespace { continue }
                guard char == "{" else { throw invalid() }
                start = index
            }
            if quoted {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { quoted = false }
            } else if char == "\"" { quoted = true }
            else if char == "{" { depth += 1 }
            else if char == "}" {
                depth -= 1
                guard depth >= 0 else { throw invalid() }
                if depth == 0, let start,
                   let bytes = text[start...index].data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                   let attributes = object["attributes"] as? [String: Any],
                   attributes["event.name"] as? String == "gemini_cli.api_response" {
                    guard let inCount = count(attributes["input_token_count"]),
                          let outCount = count(attributes["output_token_count"]),
                          let timestamp = attributes["event.timestamp"] as? String,
                          ISO8601DateFormatter().date(from: timestamp) != nil else { throw invalid() }
                    input += inCount
                    output += outCount
                    responses += 1
                    guard input.isFinite, output.isFinite else { throw invalid() }
                } else if depth == 0, let start {
                    let bytes = text[start...index].data(using: .utf8)!
                    guard (try? JSONSerialization.jsonObject(with: bytes)) != nil else { throw invalid() }
                }
                if depth == 0 { start = nil }
            }
        }
        guard depth == 0, !quoted, responses > 0 else { throw invalid() }
        return Snapshot(windows: [
            UsageWindow(label: "Gemini CLI 入力（ファイル全期間）", reportedAmount: input, reportedUnit: "tokens"),
            UsageWindow(label: "Gemini CLI 出力（ファイル全期間）", reportedAmount: output, reportedUnit: "tokens")
        ], fetchedAt: fetchedAt)
    }

    private static func count(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let amount = number.doubleValue
        return amount.isFinite && amount >= 0 && amount <= 9_007_199_254_740_991 ? amount : nil
    }

    private static func invalid() -> ParseError {
        .unsupported("Gemini CLIの指定TelemetryファイルからAPI応答のトークン実績を確認できません")
    }
}
