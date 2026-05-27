// Mac Health Keeper - ScheduleTiming の単体テスト（UC1・UC2）
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
// 01 BDD UC1/UC2 と 03 §2.3.4 のテスト仕様に 1 対 1 対応する。

import XCTest
@testable import MacHealthKit

/// ユースケース: 日次ジョブの次回実行時刻を現在時刻基準で算出する。
final class ScheduleTimingNextDailyRunTests: XCTestCase {
    private let cal = Calendar.utc          // 固定 TimeZone を注入
    private let timing = ScheduleTiming()

    /// シナリオ: 指定時刻が現在より後なら当日のその時刻を返す（01 UC1-S1）。
    func test_nextDailyRun_whenTargetIsLaterToday_returnsToday() {
        // Given: 現在が当日 08:00、hour=9 minute=0
        let now = cal.date(2026, 5, 27, 8, 0)
        // When: nextDailyRun を呼ぶ
        let next = timing.nextDailyRun(hour: 9, minute: 0, now: now, calendar: cal)
        // Then: 当日 09:00 が返る
        XCTAssertEqual(next, cal.date(2026, 5, 27, 9, 0))
    }

    /// シナリオ: 指定時刻が現在より前なら翌日のその時刻を返す（01 UC1-S2）。
    func test_nextDailyRun_whenTargetAlreadyPassed_returnsTomorrow() {
        // Given: 現在が当日 10:00、hour=9 minute=0
        let now = cal.date(2026, 5, 27, 10, 0)
        // When: nextDailyRun を呼ぶ
        let next = timing.nextDailyRun(hour: 9, minute: 0, now: now, calendar: cal)
        // Then: 翌日 09:00 が返る
        XCTAssertEqual(next, cal.date(2026, 5, 28, 9, 0))
    }
}

/// ユースケース: 経過/残り時間を人間可読の短い相対表現にする。
final class ScheduleTimingRelativeTests: XCTestCase {
    private let cal = Calendar.utc
    private let timing = ScheduleTiming()

    /// シナリオ: 数分前の時刻を短い相対表現にする（01 UC2-S1）。
    func test_relativeTimeShort_whenThreeMinutesAgo_returnsMinutesPhrase() {
        // Given: now と、その 3 分前の date
        let now = cal.date(2026, 5, 27, 12, 0)
        let date = now.addingTimeInterval(-180)
        // When: relativeTimeShort を呼ぶ
        let text = timing.relativeTimeShort(date, now: now)
        // Then: 「分」を含み「3分前」になる
        XCTAssertTrue(text.contains("分"))
        XCTAssertEqual(text, "3分前")
    }

    /// シナリオ: interval 指定で次回までの残りを表現する（01 UC2-S2）。
    func test_relativeNext_withInterval_returnsRemainingPhrase() {
        // Given: now をわずかに過ぎた直近実行 date と intervalSec=300
        let now = cal.date(2026, 5, 27, 12, 0)
        let date = now.addingTimeInterval(-10)   // 過去
        // When: relativeNext を呼ぶ
        let text = timing.relativeNext(date, intervalSec: 300, now: now, calendar: cal)
        // Then: 次回までの残りを表す「5分以内」が返る
        XCTAssertEqual(text, "5分以内")
    }
}
