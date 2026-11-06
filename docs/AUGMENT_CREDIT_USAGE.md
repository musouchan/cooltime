# Augment Enterprise usage

Add Augment Code（Enterprise利用実績） and enter `user-email|service-account-token` in the Keychain-backed field. Enterprise Analytics API access is required; this preview endpoint is not the individual Auggie session counter.

Read-only GET `/analytics/v0/credit-usage-by-user` requests seven UTC days, no date/model dimensions, 500 records per page. Reporting can lag about 90 minutes; the chosen date range excludes today and allows two hours after midnight. The API does not offer a user filter, so Cooltime must read organization pages, retain only the selected user's amount and discard other identities. It never stores or logs raw records. No entitlement, balance, reset time or shared pool is inferred.

All pages must complete. The implementation rejects malformed credits, ambiguous identities, unexpected dimensions, duplicate selected users, inconsistent period/count metadata, invalid timestamps, missing/repeated cursors, redirects and more than 20 pages. Empty results do not establish zero usage. The existing manual entry remains available.

Synthetic success/failure tests verify the documented schema, not live account values. Live validation remains pending: an authorized Enterprise service-account token and a selected user's same-date dashboard/export are required. Compare credits consumed and check permission/expired-token errors on a Mac. No token or email should be committed to the repository.

Sources (2026-11-06):
- https://docs.augmentcode.com/analytics/analytics-api
- https://docs.augmentcode.com/analytics/api-reference
