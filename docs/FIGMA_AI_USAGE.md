# Figma AI usage

Add Figma AI（Enterprise利用実績） and enter `current-email|plan-access-token` in the existing Keychain-backed field. The Enterprise administrator creates the token with only `org:ai_metering_usage_read`. Personal tokens and the connected Figma design plugin do not supply this permission.

The read-only official GET `/v1/ai_usage/daily` requests one user and seven complete UTC days, allowing six hours for reporting lag. Each displayed label states the actual date range. Seat credits consumed and shared-plan credits consumed are separate reported amounts across editor products. No plan limits, remaining allowance, or recovery time are inferred. Billing-period totals may differ from these calendar-day totals.

Pages are fetched to completion from the same fixed HTTPS host; redirects, repeated cursors, duplicate row grains, mixed users/plans, invalid amounts and partial totals are rejected. Empty results do not imply zero. Raw rows, other users' emails and tokens are not logged or persisted. The original manual Figma entry remains available.

Verified against the official schema with synthetic fixtures; authenticated API responses and Mac UI/dashboard comparison remain unverified. To validate live: use a permitted Enterprise token, select the same user and UTC days in an official daily export, compare both credit buckets, and verify expired/insufficient-scope tokens show an error without replacing the prior snapshot.

Sources (2026-11-06):
- https://developers.figma.com/docs/rest-api/ai-usage-endpoints/
- https://developers.figma.com/docs/rest-api/ai-usage/
- https://developers.figma.com/docs/rest-api/plan-access-tokens/
