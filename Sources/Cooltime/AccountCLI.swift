import Darwin
import Foundation
import CooltimeCore

enum AccountCLI {
    static func read(
        _ arguments: [String],
        name: String,
        removingEnvironmentKey: String? = nil,
        loginRequiredStatus: Int32? = nil,
        failureMessage: String
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        let localBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + localBin + ":" + inheritedPath
        if let removingEnvironmentKey { environment.removeValue(forKey: removingEnvironmentKey) }
        process.environment = environment

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let deadline = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: deadline)
        defer {
            deadline.cancel()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try? stdout.fileHandleForReading.close()
        }

        var output = Data()
        while let chunk = try stdout.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
            guard output.count + chunk.count <= 64 * 1024 else {
                throw ParseError.unsupported("\(name) CLIの応答が大きすぎます")
            }
            output.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationReason == .exit else {
            throw ParseError.unsupported("\(name) CLIが応答を完了できませんでした")
        }
        let status = process.terminationStatus
        if status == 0 { return output }
        if status == 127 { throw ParseError.unsupported("公式の\(name) CLIが見つかりません") }
        if status == loginRequiredStatus { throw ParseError.unsupported("\(name) CLIでログインしてください") }
        throw ParseError.unsupported(failureMessage)
    }
}
