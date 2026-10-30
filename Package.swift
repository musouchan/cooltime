// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cooltime",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cooltime", targets: ["Cooltime"])
    ],
    targets: [
        // 画面に依存しない中身（状態の判定・時間の表示・各サービスの取得）
        .target(name: "RecoveryCore"),
        // メニューバーと画面
        .executableTarget(name: "Cooltime", dependencies: ["RecoveryCore"]),
        .testTarget(name: "RecoveryCoreTests", dependencies: ["RecoveryCore"])
    ]
)
