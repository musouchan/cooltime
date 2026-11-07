import Foundation
import CooltimeCore

enum KreaCLI {
    static func balance(profile: String) throws -> Data {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/usr/bin", "/bin"]
        guard let executable = directories.map({ "\($0)/krea" })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ParseError.unsupported("公式Krea CLIが見つかりません")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        // The generic tool command preserves missing JSON fields instead of defaulting them to zero.
        process.arguments = ["tools", "call", "get_balance", "--input", "{}", "--json", "--profile", profile,
                             "--api-url", "https://api.krea.ai/mcp"]
        var environment = ProcessInfo.processInfo.environment
        for key in ["KREA_API_KEY", "KREA_APP_BUILDER_API_KEY", "KREA_API_URL", "KREA_PROFILE"] {
            environment.removeValue(forKey: key)
        }
        environment["PATH"] = directories.joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output

        let error = ParseError.unsupported("Krea CLIで残高を取得できません。プロファイルとログイン状態を確認してください")
        do { try process.run() } catch { throw error }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
        defer { timeout.cancel(); if process.isRunning { process.terminate() } }
        let handle = output.fileHandleForReading
        var data = Data()
        while let chunk = try handle.read(upToCount: 8192), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= 65_536 else { throw error }
        }
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { throw error }
        return data
    }
}
