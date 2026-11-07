# Salesforce Digital Wallet consumption

The official Salesforce CLI performs an authenticated read of the standard \`computeConsumption\` action (API v63.0). Enter \`target org alias|cardDefinitionDeveloperName\`. Only those identifiers are kept in Cooltime Keychain; credentials stay with the Salesforce CLI.

Cooltime selects exactly one Digital Wallet card by its exact developer name, displays its reported entitlement and consumed units, and computes a nonnegative remaining amount. It does not assume that any particular card is Agentforce, nor aggregate unrelated cards. The card name must be checked in the user's organization. The action requires a supported Enterprise/Unlimited org and Data 360.

No reset date is available from the card. An authorized org/account has not yet been tested.
