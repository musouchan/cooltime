# Kiro Enterprise daily usage automatic retrieval

Cooltime reads Kiro's official daily per-user CSV export from the customer's own S3 bucket.

Configuration stored in macOS Keychain:

`AWS profile|region|bucket|prefix|UserId or User_Email`

The AWS profile references credentials already managed by the AWS CLI. Cooltime does not copy,
store, or log AWS access keys. It invokes only a fixed AWS CLI executable from common macOS
installation paths.

Retrieval:

1. `aws s3api list-objects-v2` lists the configured bucket/prefix.
2. Only `KiroLogs/user_report` objects are accepted; the legacy
   `by_user_analytic` report is excluded to avoid double counting.
3. Only the newest valid report date is downloaded.
4. Rows matching the selected UserId or User_Email are summed across KIRO_IDE, KIRO_CLI and PLUGIN.
5. `Credits_Used` and `Overage_Credits_Used` are reported as exact daily usage.

The export does not supply a universal current monthly balance or reset timestamp, so Cooltime does
not infer either. The existing manual `sheet-16` entry remains available.

Required customer setup:

- Kiro Enterprise administrator enables granular per-user metrics.
- Kiro writes the report to the customer-controlled S3 bucket.
- The local AWS CLI profile has `s3:ListBucket`, `s3:GetObject`, and KMS decrypt permission when
  the bucket uses a customer-managed KMS key.

Official references:

- https://kiro.dev/docs/enterprise/monitor-and-track/user-activity/
- https://kiro.dev/docs/cli/enterprise/monitor-and-track/user-activity/
