import Foundation
import FoundationXML

/// JetBrains IDE's local AI Assistant quota cache. No account credential or network request is used.
public enum JetBrainsAIQuota {
    private struct Quota: Decodable {
        struct Details: Decodable {
            let current: Number
            let maximum: Number
            let available: Number?
        }
        let type: String
        let tariffQuota: Details
    }

    private struct Refill: Decodable {
        let type: String
        let next: String?
    }

    private struct Number: Decodable {
        let value: Double
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) { value = number; return }
            let text = try container.decode(String.self)
            guard let number = Double(text) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "number") }
            value = number
        }
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 262_144 else { throw invalid() }
        let delegate = Options()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.componentFound,
              let quotaText = delegate.values["quotaInfo"],
              let quotaData = quotaText.data(using: .utf8),
              quotaData.count <= 131_072,
              let quota = try? JSONDecoder().decode(Quota.self, from: quotaData),
              ["Available", "Exhausted"].contains(quota.type) else { throw invalid() }

        let used = quota.tariffQuota.current.value
        let maximum = quota.tariffQuota.maximum.value
        let available = quota.tariffQuota.available?.value
        guard valid(used), valid(maximum), maximum > 0, used <= maximum,
              available.map({ valid($0) && $0 <= maximum }) ?? true else { throw invalid() }
        if let available {
            let tolerance = max(0.01, maximum * 0.000_001)
            guard abs((used + available) - maximum) <= tolerance else { throw invalid() }
        }

        var reset: Date?
        if let refillText = delegate.values["nextRefill"],
           let refillData = refillText.data(using: .utf8),
           refillData.count <= 65_536,
           let refill = try? JSONDecoder().decode(Refill.self, from: refillData),
           refill.type == "Known", let next = refill.next {
            reset = date(next)
            guard reset != nil else { throw invalid() }
        }
        return Snapshot(windows: [
            UsageWindow(label: "JetBrains AI月間クォータ",
                        usedPercent: used / maximum * 100,
                        remainingCount: nil,
                        resetsAt: reset,
                        reportedAmount: used,
                        reportedUnit: "quota units")
        ], fetchedAt: fetchedAt)
    }

    private final class Options: NSObject, XMLParserDelegate {
        var componentFound = false
        var inComponent = false
        var values: [String: String] = [:]

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            if elementName == "component" {
                inComponent = attributeDict["name"] == "AIAssistantQuotaManager2"
                componentFound = componentFound || inComponent
            } else if inComponent, elementName == "option",
                      let name = attributeDict["name"], ["quotaInfo", "nextRefill"].contains(name),
                      let value = attributeDict["value"], values[name] == nil {
                values[name] = value
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "component" { inComponent = false }
        }

        func parser(_ parser: XMLParser, resolveExternalEntityName name: String,
                    systemID: String?) -> Data? { nil }
    }

    private static func date(_ value: String) -> Date? {
        guard !value.isEmpty, value.utf8.count <= 64 else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func valid(_ value: Double) -> Bool {
        value.isFinite && (0...9_007_199_254_740_991).contains(value)
    }

    private static func invalid() -> ParseError {
        .unsupported("JetBrains AI Assistantのローカル月間クォータを確認できません")
    }
}
