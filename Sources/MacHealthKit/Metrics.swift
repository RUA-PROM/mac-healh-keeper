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

    public init(uptimeDays: Int = 0,
                uptimeHours: Int = 0,
                loadAvg: String = "—",
                memoryFreePct: String = "—",
                compressedGB: String = "—",
                swapUsed: String = "—",
                dockerLine: String = "—",
                jobs: [String: JobStatus] = [:],
                lastUpdated: Date = .distantPast) {
        self.uptimeDays = uptimeDays
        self.uptimeHours = uptimeHours
        self.loadAvg = loadAvg
        self.memoryFreePct = memoryFreePct
        self.compressedGB = compressedGB
        self.swapUsed = swapUsed
        self.dockerLine = dockerLine
        self.jobs = jobs
        self.lastUpdated = lastUpdated
    }
}
