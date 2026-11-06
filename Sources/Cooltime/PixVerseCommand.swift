import Foundation
import CooltimeCore

enum PixVerseCommand {
    static func balance() throws -> Snapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["pixverse", "account", "info", "--json"]

        var environment = ProcessInfo.processInfo.environment
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + inheritedPath
        environment.removeValue(forKey: "PIXVERSE_ACCESS_KEY")
        process.environment = environment

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: deadline)
        defer {
            deadline.cancel()
            if process.isRunning { process.terminate() }
        }

        var output = Data()
        while let chunk = try stdout.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
            guard output.count + chunk.count <= 64 * 1024 else {
                throw ParseError.unsupported("PixVerse CLIの応答が大きすぎます")
            }
            output.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationReason == .exit else {
            throw ParseError.unsupported("PixVerse CLIが応答を完了できませんでした")
        }
        switch process.terminationStatus {
        case 0:
            return try PixVerseCLIUsage.parse(output, fetchedAt: Date())
        case 3:
            throw ParseError.unsupported("PixVerse CLIでログインしてください")
        case 127:
            throw ParseError.unsupported("公式のPixVerse CLIが見つかりません")
        default:
            throw ParseError.unsupported("PixVerse CLIで残高を取得できませんでした")
        }
    }
}
