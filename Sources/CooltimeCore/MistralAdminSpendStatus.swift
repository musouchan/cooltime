import Foundation

/// Enterprise Admin API's explicit completion spending-limit state, not a balance.
public enum MistralAdminSpendStatus {
    private struct Response: Decodable {
        struct Limits: Decodable {
            struct Completion: Decodable {
                let monthly_limit_reached: Bool
            }
            let completion: Completion
        }
        let limits: Limits
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 100_000,
              let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ParseError.unsupported("Mistral Enterpriseの月間支出上限状態を確認できません")
        }
        let reached = response.limits.completion.monthly_limit_reached
        return Snapshot(windows: [UsageWindow(label: reached ? "Mistral・組織Completion月間支出上限に到達" :
                                                      "Mistral・組織Completion月間支出上限に未到達",
                                              isLimited: reached)], fetchedAt: fetchedAt)
    }
}
