import Foundation

public enum KlingAPIPackageUsage {
    private struct Response: Decodable {
        struct Payload: Decodable {
            struct Package: Decodable {
                let resourcePackName: String
                let resourcePackId: String
                let remainingQuantity: Double
                let effectiveTime: Int64
                let invalidTime: Int64
                let status: String
            }
            let code: Int
            let resourcePackSubscribeInfos: [Package]
        }
        let code: Int
        let data: Payload
    }

    public static func url(now: Date) -> String {
        let end = Int64(now.timeIntervalSince1970 * 1000)
        let start = end - 30 * 86_400_000
        return "https://api-singapore.klingai.com/account/costs?start_time=\(start)&end_time=\(end)"
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard data.count <= 1_000_000, let response = try? decoder.decode(Response.self, from: data),
              response.code == 0, response.data.code == 0,
              response.data.resourcePackSubscribeInfos.count <= 1000 else { throw invalid() }

        let now = Int64(fetchedAt.timeIntervalSince1970 * 1000)
        var ids = Set<String>()
        var packages: [(id: String, expiry: Int64, window: UsageWindow)] = []
        for pack in response.data.resourcePackSubscribeInfos {
            guard ["online", "runOut", "toBeOnline", "expired"].contains(pack.status),
                  !pack.resourcePackId.isEmpty, ids.insert(pack.resourcePackId).inserted,
                  pack.remainingQuantity.isFinite, pack.remainingQuantity >= 0 else { throw invalid() }
            guard pack.status == "online" || pack.status == "runOut",
                  pack.effectiveTime <= now, now < pack.invalidTime else { continue }
            let name = pack.resourcePackName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 160, name.rangeOfCharacter(from: .controlCharacters) == nil
            else { throw invalid() }
            // An explicit exhausted status takes precedence over the delayed remaining quantity.
            let remaining = pack.status == "runOut" ? 0 : pack.remainingQuantity
            packages.append((pack.resourcePackId, pack.invalidTime,
                             UsageWindow(label: name, remainingCount: remaining)))
        }

        guard !packages.isEmpty else {
            throw ParseError.unsupported("直近30日を指定した照会に有効なKling APIパックがありません")
        }
        let windows = packages.sorted { ($0.expiry, $0.id) < ($1.expiry, $1.id) }.map(\.window)
        return Snapshot(windows: windows, fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Kling APIパックの残り数量を確認できません")
    }
}
