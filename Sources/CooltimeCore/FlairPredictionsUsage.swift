import Foundation

/// Counts the authenticated user's custom-model prediction jobs from Flair's
/// documented enterprise API. A job is not an image credit or a balance.
public enum FlairPredictionsUsage {
    private struct Page: Decodable {
        struct Prediction: Decodable { let id: String }
        let predictions: [Prediction]
        let nextPageCursor: String?
        let hasMore: Bool
    }

    public static func url(cursor: String? = nil) throws -> String {
        var parts = URLComponents(string: "https://enterprise-api-v1.flair.ai/custom-model-prediction")!
        if let cursor {
            guard !cursor.isEmpty, cursor.utf8.count <= 2048 else { throw invalid() }
            parts.queryItems = [URLQueryItem(name: "lastDocId", value: cursor)]
        }
        guard let url = parts.string else { throw invalid() }
        return url
    }

    public static func fetch(fetchedAt: Date, get: (String) async throws -> Data) async throws -> Snapshot {
        var cursor: String?
        var cursors = Set<String>()
        var ids = Set<String>()
        for _ in 0..<100 {
            let data = try await get(url(cursor: cursor))
            guard data.count <= 8_000_000,
                  let page = try? JSONDecoder().decode(Page.self, from: data),
                  page.predictions.count <= 10_000 else { throw invalid() }
            for prediction in page.predictions {
                guard !prediction.id.isEmpty, prediction.id.utf8.count <= 128,
                      ids.insert(prediction.id).inserted else { throw invalid() }
            }
            if !page.hasMore {
                return Snapshot(windows: [UsageWindow(label: "Flair Enterprise予測ジョブ・一覧全件",
                                                      reportedAmount: Double(ids.count), reportedUnit: "jobs")],
                                fetchedAt: fetchedAt)
            }
            guard !page.predictions.isEmpty,
                  let next = page.nextPageCursor, !next.isEmpty, next.utf8.count <= 2048,
                  cursors.insert(next).inserted else { throw invalid() }
            cursor = next
        }
        throw invalid()
    }

    private static func invalid() -> ParseError {
        .unsupported("Flair Enterprise APIの予測ジョブ一覧を完全に確認できません")
    }
}
