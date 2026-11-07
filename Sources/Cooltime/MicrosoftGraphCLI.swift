import Foundation
import CooltimeCore

enum MicrosoftGraphCLI {
    /// Reuses the user's Azure CLI login; a tenant admin must consent to Reports.Read.All.
    static func accessToken(tenantID: String) throws -> String {
        let candidates = ["/opt/homebrew/bin/az", "/usr/local/bin/az", "/usr/bin/az"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { throw ParseError.unsupported("Azure CLIが見つかりません") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["account", "get-access-token", "--tenant", tenantID,
                             "--scope", "https://graph.microsoft.com/Reports.Read.All",
                             "--output", "json", "--only-show-errors"]
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
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = object["accessToken"] as? String,
                  !token.isEmpty, token.utf8.count <= 16_384,
                  token.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw ParseError.unsupported("Azure CLIのGraph権限を確認できません（Reports.Read.Allと管理者同意が必要）")
            }
            return token
        } catch let error as ParseError { throw error }
        catch { throw ParseError.unsupported("Azure CLIを実行できません") }
    }
}
