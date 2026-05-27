// Mac Health Keeper - ScheduleTiming（純粋ロジック）
//
// 時刻計算・相対時刻表示の純粋ロジックを集約する値型。
// AppKit / 外部コマンドに依存せず、現在時刻（now）と Calendar を引数で受け取るため、
// テストから固定入力で出力を検証できる。
//
// 分岐ロジックは src/MacHealth.swift L186-242 の原文を維持し、
// `Date()` / `Calendar.current` の直読みを引数化したのみ（挙動は不変）。

import Foundation

public struct ScheduleTiming {

    public init() {}

    /// 指定時刻が now 以前なら翌日、後なら当日の hour:minute:00 の Date を返す。
    /// （src/MacHealth.swift `nextDailyRun(hour:minute:)` L186-198 と同一ロジック）
    public func nextDailyRun(hour: Int,
                             minute: Int,
                             now: Date,
                             calendar: Calendar = Calendar.current) -> Date {
        let cal = calendar
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        var next = cal.date(from: comps) ?? now
        if next <= now {
            next = cal.date(byAdding: .day, value: 1, to: next) ?? next
        }
        return next
    }

    /// 「未来」「今」「N分前」「N時間前」「N日前」など経過時間を短い文字列に整形する。
    /// （src/MacHealth.swift `relativeTimeShort(_:)` L203-210 と同一ロジック）
    public func relativeTimeShort(_ date: Date, now: Date) -> String {
        let elapsed = Int(now.timeIntervalSince(date))
        if elapsed < 0  { return "未来" }
        if elapsed < 60 { return "今" }
        if elapsed < 3600 { return "\(elapsed / 60)分前" }
        if elapsed < 86400 { return "\(elapsed / 3600)時間前" }
        return "\(elapsed / 86400)日前"
    }

    /// 「N分以内」「まもなく」「あとN分」「今日 HH:mm」「明日 HH:mm」「M/d HH:mm」へ整形する。
    /// （src/MacHealth.swift `relativeNext(_:intervalSec:)` L213-242 と同一ロジック）
    public func relativeNext(_ date: Date,
                             intervalSec: Int? = nil,
                             now: Date,
                             calendar: Calendar = Calendar.current) -> String {
        let elapsed = date.timeIntervalSince(now)
        if elapsed < 0 {
            // 過ぎている場合
            if let iv = intervalSec {
                return "\(iv / 60)分以内"
            }
            return "まもなく"
        }
        if elapsed < 60 {
            return "まもなく"
        }
        let cal = calendar
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        if cal.isDateInToday(date) {
            fmt.dateFormat = "HH:mm"
            // 1 時間以内は分表示
            if elapsed < 3600 {
                return "あと\(Int(elapsed) / 60)分"
            }
            return "今日 \(fmt.string(from: date))"
        }
        if cal.isDateInTomorrow(date) {
            fmt.dateFormat = "HH:mm"
            return "明日 \(fmt.string(from: date))"
        }
        fmt.dateFormat = "M/d HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - テスト補助（固定 Calendar / Date 生成）

public extension Calendar {
    /// テストで時刻のぶれを防ぐための UTC 固定 Calendar。
    static var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// 年月日時分から Date を生成するテスト補助ヘルパ（秒は 0）。
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return self.date(from: comps)!
    }
}
