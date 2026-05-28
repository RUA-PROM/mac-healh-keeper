// swift-tools-version:5.7
// Mac Health Keeper - SwiftPM 構成（テスト専用）
//
// Functional Core（ScheduleTiming / MetricsParser / MetricsSnapshot・JobStatus / JobCatalog /
// MenuModel / ShellRunner / JobController）の library target と XCTest target を定義する。
// 新規ファイルは path: "Sources/MacHealthKit" のため自動で含まれる（targets の変更不要）。
// 配布ビルドは install.sh の swiftc を使い、本 Package.swift は配布物に含めない。
// AppKit / Cocoa には依存しない（Foundation のみ）。

import PackageDescription

let package = Package(
    name: "MacHealthKit",
    products: [
        .library(name: "MacHealthKit", targets: ["MacHealthKit"]),
    ],
    targets: [
        .target(
            name: "MacHealthKit",
            path: "Sources/MacHealthKit"
        ),
        .testTarget(
            name: "MacHealthKitTests",
            dependencies: ["MacHealthKit"],
            path: "Tests/MacHealthKitTests"
        ),
    ]
)
