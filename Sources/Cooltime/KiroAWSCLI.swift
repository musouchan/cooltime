import Foundation
import CooltimeCore

enum KiroAWSCLI {
    static func fetch(config: KiroEnterpriseUsage.Configuration, fetchedAt: Date) throws -> Snapshot {
        let listing = try run([
            "s3api", "list-objects-v2", "--bucket", config.bucket, "--prefix", config.prefix,
            "--profile", config.profile, "--region", config.region, "--output", "json", "--no-cli-pager"
        ], maximumBytes: 8_000_000)
        let keys = try KiroEnterpriseUsage.reportKeys(from: listing)
        let files = try keys.map { key in
            try run([
                "s3", "cp", "s3://\(config.bucket)/\(key)", "-",
                "--profile", config.profile, "--region", config.region, "--only-show-errors",
                "--no-cli-pager"
            ], maximumBytes: 10_000_000)
        }
        return try KiroEnterpriseUsage.parse(csvFiles: files, userSelector: config.userSelector,
                                             fetchedAt: fetchedAt)
    }

    private static func run(_ arguments: [String], maximumBytes: Int) throws -> Data {
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
                  data.count <= maximumBytes else {
                throw ParseError.unsupported("AWS CLIでKiro利用レポートを取得できません")
            }
            return data
        } catch let error as ParseError {
            throw error
        } catch {
            throw ParseError.unsupported("AWS CLIを実行できません")
        }
    }
}
