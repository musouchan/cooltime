# You.com API Platform balance

Official read-only GET https://api.you.com/v1/billing/account_balance with X-API-Key.
The user supplies a Platform API key through the existing Keychain-backed field.
Organization members receive the entire organization's shared balance; individual accounts receive their own balance.
This is not the You.com consumer subscription allowance or a per-key spending cap.

The documented numeric balance is in USD cents and may be fractional. Divide by 100 without truncating.
Missing/null/invalid balances and non-account resources fail; an explicit zero is valid.
No reset time is supplied or inferred. No generation/search request or automatic top-up is performed.
Requests use the existing ephemeral transport with redirects disabled. Raw account IDs and tokens are not persisted.

Six synthetic tests cover the official example, zero, malformed responses, resource identity, numeric errors and manual coexistence.
Real API authentication, organization membership, dashboard comparison and macOS UI remain unverified.
To validate on a Mac, compare the same account/organization's Platform Billing balance; verify revoked keys show an error.

Sources checked 2026-11-07:
- https://you.com/docs/api-reference/billing/get-account-balance
- https://you.com/docs/administration/billing
