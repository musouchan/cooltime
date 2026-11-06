import Foundation
import CooltimeCore

enum PixVerseCommand {
    static func balance() throws -> Snapshot {
        let output = try AccountCLI.read(
            ["pixverse", "account", "info", "--json"],
            name: "PixVerse",
            removingEnvironmentKey: "PIXVERSE_ACCESS_KEY",
            loginRequiredStatus: 3,
            failureMessage: "PixVerse CLIで残高を取得できませんでした"
        )
        return try PixVerseCLIUsage.parse(output, fetchedAt: Date())
    }
}
