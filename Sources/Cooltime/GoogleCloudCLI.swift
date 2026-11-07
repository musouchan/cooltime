import Foundation
import CooltimeCore

enum GoogleCloudCLI {
    static func accessToken(applicationDefault: Bool = false) throws -> String {
        let candidates = ["/opt/homebrew/bin/gcloud", "/usr/local/bin/gcloud", "/usr/bin/gcloud"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { throw ParseError.unsupported("Google Cloud CLIが見つかりません") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = applicationDefault
            ? ["auth", "application-default", "print-access-token", "--quiet"]
            : ["auth", "print-access-token", "--quiet"]
        process.environment = ProcessInfo.processInfo.environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationReason == .exit, process.terminationStatus == 0,
                  data.count <= 20_000,
                  let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !token.isEmpty, token.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw ParseError.unsupported("gcloud認証トークンを取得できません")
            }
            return token
        } catch let error as ParseError { throw error }
        catch { throw ParseError.unsupported("gcloudを実行できません") }
    }
}
