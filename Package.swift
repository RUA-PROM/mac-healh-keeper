// swift-tools-version:5.7
// Mac Health Keeper - SwiftPM 構成（テスト専用）
//
// Functional Core（ScheduleTiming / MetricsParser / MetricsSnapshot・JobStatus / JobCatalog /
// MenuModel / ShellRunner / JobController / MetricsCollectorPolicy）の library target と
// XCTest target を定義する。
// 新規ファイルは path: "Sources/MacHealthKit" のため自動で含まれる（targets の変更不要）。
// 配布ビルドは install.sh の swiftc を使い、本 Package.swift は配布物に含めない。
// AppKit / Cocoa には依存しない（Foundation のみ）。
//
// `MacHealthCheck` executable target（issue: 20260529_083530_メトリクス非表示修正 フォロー）:
//   XCTest / swift-testing 非搭載環境（Command Line Tools のみ等）でも回帰検知ができるよう、
//   純粋関数の BDD アサーションを `swift run MacHealthCheck` 1 本で実行する。
//   `make test-swift-purecore` から呼ばれ、`make check` の必須経路として常に実行される。

import PackageDescription

let package = Package(
    name: "MacHealthKit",
    products: [
        .library(name: "MacHealthKit", targets: ["MacHealthKit"]),
        .executable(name: "MacHealthCheck", targets: ["MacHealthCheck"]),
    ],
    targets: [
        .target(
            name: "MacHealthKit",
            path: "Sources/MacHealthKit"
        ),
        .executableTarget(
            name: "MacHealthCheck",
            dependencies: ["MacHealthKit"],
            path: "Sources/MacHealthCheck"
        ),
        .testTarget(
            name: "MacHealthKitTests",
            dependencies: ["MacHealthKit"],
            path: "Tests/MacHealthKitTests"
        ),
    ]
)
