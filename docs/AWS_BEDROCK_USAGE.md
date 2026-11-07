# Amazon Bedrock usage

Cooltime reads exact Amazon Bedrock runtime metrics from the official `AWS/Bedrock` CloudWatch namespace by running the installed AWS CLI. It requests `InputTokenCount`, `OutputTokenCount`, and `Invocations` with the `ModelId` dimension for the previous seven complete UTC days.

Enter `AWS profile|region|model ID`. Cooltime stores only those identifiers in Keychain. AWS credentials remain in the user's existing AWS CLI credential chain and are never copied into Cooltime.

CloudWatch reports consumption, not a monthly subscription allowance. Cooltime therefore does not invent a remaining balance or reset time. The IAM identity needs `cloudwatch:GetMetricData` for the selected account and region. Account validation remains pending where no Bedrock account is available.
