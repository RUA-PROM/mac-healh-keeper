// Mac Health Keeper - JobCatalog（Domain・ジョブの静的定義）
//
// 現 src/MacHealth.swift L43-68 の jobs / jobShortNames / jobFrequencies /
// jobSchedules / ScheduleKind と launchd ラベル規則を移設したもの。
// 並び順・短名・頻度・スケジュール・ラベル規則は現状不変。AppKit 非依存。

import Foundation

/// ジョブごとの実行スケジュール種別（インターバル系 or カレンダー系）。
/// 現 AppDelegate.ScheduleKind と同一。
public enum ScheduleKind: Equatable {
    case interval(Int)
    case daily(Int, Int)
}

/// ジョブ ID・短名・頻度・スケジュール種別・launchd ラベル規則の静的定義。
public struct JobCatalog {

    public init() {}

    /// ジョブ ID の並び（表示順・現状不変）。
    public let jobs = ["monitor", "docker", "uptime", "refresh"]

    /// ジョブの短い名前。
    public let shortNames: [String: String] = [
        "monitor": "メモリ／負荷監視",
        "docker":  "Dockerアイドル監視",
        "uptime":  "長期稼働の通知",
        "refresh": "アプリ自動再起動"
    ]

    /// 表示用の頻度。
    public let frequencies: [String: String] = [
        "monitor": "5分毎",
        "docker":  "10分毎",
        "uptime":  "毎日 9:00",
        "refresh": "毎日 3:00"
    ]

    /// ジョブごとの実行スケジュール種別。
    public let schedules: [String: ScheduleKind] = [
        "monitor": .interval(300),
        "docker":  .interval(600),
        "uptime":  .daily(9, 0),
        "refresh": .daily(3, 0)
    ]

    /// launchd ラベル規則 `com.github.adachi-tatsuru.machealth.<job>`（現状不変）。
    public func label(for job: String) -> String {
        return "com.github.adachi-tatsuru.machealth.\(job)"
    }
}
