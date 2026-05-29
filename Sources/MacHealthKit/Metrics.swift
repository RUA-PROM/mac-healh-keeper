// Mac Health Keeper - メトリクス/ジョブ状態モデル（Domain・純粋値型）
//
// 現 src/MacHealth.swift L11-28 の MetricsSnapshot / JobStatus を移設したもの。
// フィールド・既定値・意味は現状不変。AppKit に依存しない（Foundation のみ）。

import Foundation

/// 各ジョブの状態スナップショット。
public struct JobStatus: Equatable {
    public var loaded: Bool
    public var lastRun: Date?
    public var nextRun: Date?

    public init(loaded: Bool = false, lastRun: Date? = nil, nextRun: Date? = nil) {
        self.loaded = loaded
        self.lastRun = lastRun
        self.nextRun = nextRun
    }
}

/// メトリクスのスナップショット（キャッシュ用）。
///
/// `collectorErrors` は MetricsCollector が収集経路の不整合（例: metrics.sh 未配置）を
/// 検出した際に追加する任意フィールド。MenuModel が空でない場合に警告ラベルを描画する。
/// 既定 `[]` のため、既存呼び出し・既存テストへの影響はない（issue: 20260529_083530_メトリクス非表示修正）。
public struct MetricsSnapshot: Equatable {
    public var uptimeDays: Int
    public var uptimeHours: Int
    public var loadAvg: String
    public var memoryFreePct: String
    public var compressedGB: String
    public var swapUsed: String
    public var dockerLine: String
    public var jobs: [String: JobStatus]
    public var lastUpdated: Date
    public var collectorErrors: [String]

    public init(uptimeDays: Int = 0,
                uptimeHours: Int = 0,
                loadAvg: String = "—",
                memoryFreePct: String = "—",
                compressedGB: String = "—",
                swapUsed: String = "—",
                dockerLine: String = "—",
                jobs: [String: JobStatus] = [:],
                lastUpdated: Date = .distantPast,
                collectorErrors: [String] = []) {
        self.uptimeDays = uptimeDays
        self.uptimeHours = uptimeHours
        self.loadAvg = loadAvg
        self.memoryFreePct = memoryFreePct
        self.compressedGB = compressedGB
        self.swapUsed = swapUsed
        self.dockerLine = dockerLine
        self.jobs = jobs
        self.lastUpdated = lastUpdated
        self.collectorErrors = collectorErrors
    }
}
