# Freepik / Magnific Business・Enterprise チーム消費

公式 Analytics API の `POST /v1/analytics/team-credit-usage` から、前の完全な7 UTC日間のチームAIクレジット消費と利用回数を取得します。Dashboard/CSVと同じ利用実績で、API照会自体にクレジットは掛かりません。契約残高・回復時刻は公開応答にないため推定しません。手動入力も残ります。

BusinessまたはEnterpriseのチームAPIキーをCooltimeのKeychainに入力します。個人プランではAnalytics APIは使えません。`tool_name` ごとに同じ値の行が現れても異なる消費の可能性があるため、明示された全行を加算します。実チーム検証は未実施です。

公式資料: https://docs.magnific.com/api-reference/analytics/overview 、https://docs.magnific.com/api-reference/analytics/team-credit-usage/query
