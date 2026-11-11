import Foundation

/// この Mac に入っているサービスを、見つけるための手がかり。
/// アプリは Bundle ID（アイコンを借りるのにも使う）、ターミナルのツールや VS Code の拡張は、ホームの下のファイルで見つける。
/// 見つけるのは、ファイルやアプリがあるかどうかだけ。中身は読まない。
/// キーは、サービスの ID か名前。覚えている範囲で書いたもので、違っていても、見つからないだけ。
enum Detection {
    static let bundleIDs: [String: [String]] = [
        "sheet-11": ["com.google.antigravity"],
        "Cursor 個人": ["com.todesktop.230313mzl4w4u92"],
        "Windsurf": ["com.exafunction.windsurf"],
        "Zed AI": ["dev.zed.Zed"],
        "kiro-enterprise-usage": ["dev.kiro.desktop"],
        "jetbrains-ai-local-quota": ["com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm", "com.jetbrains.pycharm.ce",
                                     "com.jetbrains.WebStorm", "com.jetbrains.goland", "com.jetbrains.rubymine", "com.jetbrains.rider",
                                     "com.jetbrains.CLion", "com.jetbrains.PhpStorm", "com.jetbrains.datagrip"],
        "figma-ai-usage": ["com.figma.Desktop"],
        "Perplexity": ["ai.perplexity.mac"],
        "Notion AI": ["notion.id"],
        "Grammarly": ["com.grammarly.ProjectLlama"],
        "CapCut AI": ["com.lemon.lvoverseas"],
        "Descript": ["com.descript.beachcube"],
        "Granola": ["com.granola.app"],
        "Adobe Firefly / Photoshop / Illustrator / Express": ["com.adobe.Photoshop", "com.adobe.illustrator"],
    ]

    /// ホームからの相対パス。最後の部分が「*」で終わるものは、その前の文字で始まる名前を探す。
    static let homePaths: [String: [String]] = [
        "sheet-11": [".gemini/antigravity"],
        "gemini-cli-local-usage": [".gemini"],
        "aider-local-usage": [".aider.conf.yml"],
        "opencode-go-usage": [".local/share/opencode", ".config/opencode"],
        "Cursor 個人": [".cursor"],
        "Windsurf": [".codeium/windsurf"],
        "kiro-enterprise-usage": [".kiro"],
        "Cline": [".vscode/extensions/saoudrizwan.claude-dev-*"],
        "Roo Code": [".vscode/extensions/rooveterinaryinc.roo-cline-*"],
        "Kilo Code": [".vscode/extensions/kilocode.kilo-code-*"],
        "Continue": [".continue", ".vscode/extensions/continue.continue-*"],
    ]
}

extension ServiceDef {
    /// アイコンを借りたり、入っているかを調べたりする、アプリの Bundle ID。
    public var appBundleIDs: [String] { bundleIDs + (Detection.bundleIDs[id] ?? Detection.bundleIDs[name] ?? []) }
    /// 入っているかを調べる、ホームの下のパス。
    public var detectHomePaths: [String] { Detection.homePaths[id] ?? Detection.homePaths[name] ?? [] }
}
