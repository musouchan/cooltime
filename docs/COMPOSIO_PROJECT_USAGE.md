# Composio Project Usage Summary

プロジェクト API キーを Cooltime の Keychain に設定すると、公式 `POST /api/v3.1/project/usage/summary` から前の完全な7 UTC 日間のエンティティ別利用量を取得します。`total_quantity` の単位をそのまま表示し、`instant_charge` に通貨情報がないため請求額には転用しません。組織全体の残高・契約枠・回復日時は取得しません。手動入力も維持します。

公式: https://docs.composio.dev/reference/api-reference/projects/postProjectUsageSummary

Composioのプロジェクトキーが必要です。実アカウントは未検証です。組織全体を知るには別のOrg API keyとOrg Usage Summaryの権限が必要で、Cooltimeは個別プロジェクトのみを示します。
