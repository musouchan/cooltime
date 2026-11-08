import Foundation
import CooltimeCore

enum AzureMonitorCLI {
    static func fetch(config: AzureFoundryMonitorUsage.Configuration,
                      period: AzureFoundryMonitorUsage.Period,
                      fetchedAt: Date) throws -> Snapshot {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let data = try run([
            "monitor", "metrics", "list", "--resource", config.resourceID,
            "--metrics", "ProcessedPromptTokens", "GeneratedTokens", "TokenTransaction",
            "--aggregation", "Total", "--interval", "P1D",
            "--start-time", iso.string(from: period.start), "--end-time", iso.string(from: period.end),
            "--subscription", config.subscriptionID, "--output", "json", "--only-show-errors"
        ])
        return try AzureFoundryMonitorUsage.parse(data, period: period, fetchedAt: fetchedAt)
    }

    private static func run(_ arguments: [String]) throws -> Data {
        let candidates = ["/opt/homebrew/bin/az", "/usr/local/bin/az", "/usr/bin/az"]
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { throw ParseError.unsupported("Azure CLIが見つかりません") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationReason == .exit, process.terminationStatus == 0,
                  data.count <= 8_000_000 else {
                throw ParseError.unsupported("Azure CLIでFoundryメトリクスを取得できません")
            }
            return data
        } catch let error as ParseError {
            throw error
        } catch {
            throw ParseError.unsupported("Azure CLIを実行できません")
        }
    }
}
