# Microsoft Foundry usage

Cooltime runs the installed Azure CLI and reads exact Azure Monitor totals for a \`Microsoft.CognitiveServices/accounts\` resource. It requests \`ProcessedPromptTokens\`, \`GeneratedTokens\`, and \`TokenTransaction\` for the previous seven complete UTC days.

Enter \`subscription UUID|resource group|account name\`. Cooltime stores only these resource identifiers. Azure credentials stay in the Azure CLI login/session and are not copied into Cooltime. The signed-in identity needs permission to read metrics, such as Monitoring Reader.

Azure Monitor exposes consumption, not a universal subscription allowance. Cooltime therefore does not infer a remaining balance or reset time. Real-account validation is pending.
