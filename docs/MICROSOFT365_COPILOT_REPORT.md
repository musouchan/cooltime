# Microsoft 365 Copilot 利用レポート

Graph v1.0 `getMicrosoft365CopilotUsageUserDetail(period='D7',version='v2')` の公式CSVから、指定ライセンスユーザーの直近7日プロンプト数を読む連携です。契約残クレジット・個人の日次残枠・回復時刻は報告しません。従来の手動入力も残ります。

Azure CLI に対象テナントの管理者/Reports Readerでサインインし、`Reports.Read.All` の管理者同意を得てから、Cooltimeに `tenant UUID|ユーザープリンシパル名` を設定します。更新時のみ Azure CLI のOAuthトークンをメモリ内で取得し、Graph v1.0に送信します。テナント全体のCSVはメモリ内で指定ユーザーだけ読み、保存しません。レポートがユーザー名を匿名化している場合やアクセス権不足では取得エラーにします。実テナント検証は未実施です。

公式資料: https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/reports/copilotreportroot-getmicrosoft365copilotusageuserdetail および https://learn.microsoft.com/en-us/graph/reportroot-authorization
