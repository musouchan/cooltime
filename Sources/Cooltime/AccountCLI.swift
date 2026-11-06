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
        let expires = DispatchTime.now() + 20
        DispatchQueue.global().asyncAfter(deadline: expires, execute: deadline)
        defer {
            deadline.cancel()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try? stdout.fileHandleForReading.close()
        }

        var output = Data()
        let descriptor = stdout.fileHandleForReading.fileDescriptor
        var buffer = [UInt8](repeating: 0, count: 4096)
        // Even if a CLI wrapper spawns a child, inherited stdout must not keep this read blocked.
        while true {
            guard DispatchTime.now() < expires else {
                throw ParseError.unsupported("\(name) CLIの応答がタイムアウトしました")
            }
            var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&event, 1, 250)
            if ready == 0 || (ready < 0 && errno == EINTR) { continue }
            guard ready > 0 else { throw ParseError.unsupported(failureMessage) }
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ParseError.unsupported(failureMessage) }
            guard output.count + count <= 64 * 1024 else {
                throw ParseError.unsupported("\(name) CLIの応答が大きすぎます")
            }
            output.append(contentsOf: buffer.prefix(count))
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
