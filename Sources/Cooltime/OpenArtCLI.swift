import Foundation

/// Executes only the read-only account command using credentials already owned by the official CLI.
enum OpenArtCLI {
    static func account() throws -> Data {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let locations = ["/opt/homebrew/bin/openart", "/usr/local/bin/openart",
                         "\(home)/.local/bin/openart"]
        guard let path = locations.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            throw ParseError.unsupported("OpenArt公式CLIが見つかりません")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["account", "--json", "--no-input"]
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw ParseError.unsupported("OpenArt公式CLIを起動できません") }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: killer)
        defer { killer.cancel(); if process.isRunning { process.terminate() } }
        var data = Data()
        while true {
            let chunk = stdout.fileHandleForReading.availableData
            data.append(chunk)
            guard data.count <= 131_072 else { throw ParseError.unsupported("OpenArt CLIの応答が大きすぎます") }
            if chunk.isEmpty { break }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else {
            throw ParseError.unsupported("OpenArt CLIで残高を確認できません。openart loginと選択中ワークスペースを確認してください")
        }
        return data
    }
}
