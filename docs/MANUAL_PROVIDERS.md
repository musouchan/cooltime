# Cooltime manual-only providers (2026-11-05)

This is the manual entry fallback for the 166 services marked `未登録` in the tracking Google Sheet. Each service has a stable identifier based on the **original sheet row** (e.g. `sheet-11` = Google Antigravity). These IDs must **not** be renumbered: stored accounts reference them.

## What this does
- Search and add any of the 166 manual-only services.
- Save a numeric balance, unit, observation time, and source.
- Optionally save a reset date **only when actually shown by the provider**.
- Import one or many rows from a user-provided UTF-8 CSV (up to 1 MB and at most 500 observations per import).
- Retain the 500 most recent manual observations per account in the existing local application state; the latest observed row is displayed.
- Preserve existing 18 live integrations and never make an API request for a manual-only service.
- Exclude all manual observations from live menubar status calculations to prevent stale, device-local or user-reported values from masquerading as account-wide real-time balances.

## CSV format

```csv
remaining,unit,observed_at,reset_at,source
250,credits,2026-11-05T13:00:00+09:00,,"Official billing dashboard"
10,requests,2026-11-05T13:25:00+09:00,2026-11-06T00:00:00+09:00,"Provider quota screen"
```

`reset_at` is optional. All timestamps must be ISO 8601 and include an explicit timezone. `remaining` must be finite and nonnegative. `source` and `unit` are required. The app does **not** use passwords, cookies or screenshots to parse the manual entry.

## Verification
GitHub Actions on macOS runs `swift test` and the full app build. **An automated test cannot prove that a user-entered number matches the provider's true balance.** Manual support is a functional fallback only, and these entries must remain classified as manual rather than verified API integrations.

## Further work
- Confirm individual provider APIs / CLI support and replace manual-only entries one by one.
- Add audit and export UI for observation history (records are already persisted).
- Integrate PR #13 Spark independently. The combined catalog will have 185 services (18 existing + 166 manual + Spark).
- A single manual record is never account-wide verified; show observation date and source when displayed.
