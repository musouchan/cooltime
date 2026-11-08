import Foundation
import CooltimeCore

enum SalesforceCLI {
    static func fetch(config: SalesforceDigitalWalletUsage.Configuration, fetchedAt: Date) throws -> Snapshot {
        let candidates = ["/opt/homebrew/bin/sf", "/usr/local/bin/sf", "/usr/bin/sf"]
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { throw ParseError.unsupported("Salesforce CLIが見つかりません") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["api", "request", "rest",
                             "/services/data/v63.0/actions/standard/computeConsumption",
                             "--method", "GET", "--target-org", config.orgAlias]
        process.environment = ProcessInfo.processInfo.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationReason == .exit, process.terminationStatus == 0,
                  data.count <= 2_000_000 else {
                throw ParseError.unsupported("Salesforce CLIでDigital Walletを取得できません")
            }
            return try SalesforceDigitalWalletUsage.parse(data, cardName: config.cardName, fetchedAt: fetchedAt)
        } catch let error as ParseError {
            throw error
        } catch {
            throw ParseError.unsupported("Salesforce CLIを実行できません")
        }
    }
}
