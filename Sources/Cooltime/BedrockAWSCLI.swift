import Foundation
import CooltimeCore

enum BedrockAWSCLI {
    static func fetch(config: BedrockCloudWatchUsage.Configuration,
                      period: BedrockCloudWatchUsage.Period,
                      fetchedAt: Date) throws -> Snapshot {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let query = try BedrockCloudWatchUsage.queryJSON(modelID: config.modelID)
        let data = try run([
            "cloudwatch", "get-metric-data", "--metric-data-queries", query,
            "--start-time", iso.string(from: period.start), "--end-time", iso.string(from: period.end),
            "--scan-by", "TimestampAscending", "--profile", config.profile, "--region", config.region,
            "--output", "json", "--no-cli-pager"
        ])
        return try BedrockCloudWatchUsage.parse(data, period: period, fetchedAt: fetchedAt)
    }

    private static func run(_ arguments: [String]) throws -> Data {
        let candidates = ["/opt/homebrew/bin/aws", "/usr/local/bin/aws", "/usr/bin/aws"]
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            throw ParseError.unsupported("AWS CLIが見つかりません")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["AWS_PAGER"] = ""
        environment["AWS_CLI_AUTO_PROMPT"] = "off"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationReason == .exit, process.terminationStatus == 0,
                  data.count <= 4_000_000 else {
                throw ParseError.unsupported("AWS CLIでBedrockメトリクスを取得できません")
            }
            return data
        } catch let error as ParseError {
            throw error
        } catch {
            throw ParseError.unsupported("AWS CLIを実行できません")
        }
    }
}
