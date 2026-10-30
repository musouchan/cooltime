// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cooltime",
    platforms: [.macOS(.v14)],
    targets: [
        // 画面に依存しない部分（時刻の計算・状態の判定・応答の読み取り）。時計を差し替えてテストできる。
        .target(name: "CooltimeCore"),
        // メニューバーアプリ本体（SwiftUI）。
        .executableTarget(name: "Cooltime", dependencies: ["CooltimeCore"]),
        .testTarget(name: "CooltimeCoreTests", dependencies: ["CooltimeCore"]),
    ]
)
