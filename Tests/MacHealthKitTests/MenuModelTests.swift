// Mac Health Keeper - MenuModel（UI 純粋部）の単体テスト（T6）
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
// 01 UC1-S1 と 03 §2.6.4 のテスト仕様に対応する。
// 分割前の rebuildMenu（src/MacHealth.swift L210-365）が生成していた項目列を期待値として固定する。

import XCTest
@testable import MacHealthKit

/// ユースケース: MenuModel が MetricsSnapshot から現状と同一の項目・順序のメニューデータを生成する。
final class MenuModelTests: XCTestCase {
    private let cal = Calendar.utc
    private let timing = ScheduleTiming()
    private let catalog = JobCatalog()

    private func fixedSnapshot() -> MetricsSnapshot {
        var snap = MetricsSnapshot()
        snap.uptimeDays = 1; snap.uptimeHours = 2
        snap.loadAvg = "1.23"; snap.memoryFreePct = "78"
        snap.compressedGB = "1.0 GB"; snap.swapUsed = "512.00M"
        snap.dockerLine = "Docker:         停止中"
        snap.lastUpdated = cal.date(2026, 5, 27, 12, 0)
        snap.jobs = [
            "monitor": JobStatus(loaded: true, lastRun: cal.date(2026, 5, 27, 11, 57), nextRun: nil),
            "docker":  JobStatus(loaded: false, lastRun: nil, nextRun: nil),
            // nextRun は実クロック依存の「今日/明日」を避け、決定的な "M/d HH:mm" になる遠い将来日にする。
            // （relativeNext は Calendar.isDateInToday/Tomorrow が実時刻を参照するため。サブ A の既存仕様）
            "uptime":  JobStatus(loaded: true, lastRun: nil, nextRun: cal.date(2026, 12, 25, 9, 0)),
            "refresh": JobStatus(loaded: false, lastRun: nil, nextRun: nil),
        ]
        return snap
    }

    /// シナリオ: 同一入力に対し分割前と同じ項目列・順序を生成する（01 UC1-S1）。
    func test_build_withFixedSnapshot_producesSameTitlesAndOrder() {
        // Given: lastUpdated を持つ固定スナップショットと固定 now（UTC で安定化）
        let snap = fixedSnapshot()
        let now = cal.date(2026, 5, 27, 12, 0)

        // When: build を呼ぶ
        let specs = MenuModel().build(snapshot: snap, catalog: catalog, timing: timing, now: now, calendar: cal)

        // Then: 先頭がタイトル（disabled）で、メトリクス行・順序が現状どおり
        XCTAssertEqual(specs.first?.title, "Mac Health Keeper")
        XCTAssertEqual(specs.first?.kind, .disabled)
        let titles = specs.map { $0.title }
        XCTAssertTrue(titles.contains("  稼働時間:       1日 2時間"))
        XCTAssertTrue(titles.contains("  負荷平均(1分):  1.23"))
        XCTAssertTrue(titles.contains("  空きメモリ:     78%"))
        XCTAssertTrue(titles.contains("  圧縮メモリ:     1.0 GB"))
        XCTAssertTrue(titles.contains("  スワップ使用:   512.00M"))
        XCTAssertTrue(titles.contains("  Docker:         停止中"))
        // And (Then): 最終更新行（⌘R）が現状の文言・keyEquivalent で入る
        XCTAssertTrue(titles.contains("  最終更新: 12:00:00  (⌘R で更新)"))
        XCTAssertTrue(specs.contains { $0.action == .refreshNow && $0.keyEquivalent == "r" })
        // And (Then): toggleJob アクションを持つジョブ項目が JobCatalog.jobs の順で 4 件
        let toggleJobs = specs.filter { $0.action == .toggleJob }.compactMap { $0.representedJob }
        XCTAssertEqual(toggleJobs, ["monitor", "docker", "uptime", "refresh"])
        // And (Then): runJob 項目も 4 件、終了は ⌘Q
        XCTAssertEqual(specs.filter { $0.action == .runJob }.count, 4)
        XCTAssertTrue(specs.contains { $0.action == .terminate && $0.keyEquivalent == "q" && $0.title == "Mac Health を終了" })
    }

    /// シナリオ: 全項目の title 列が分割前の rebuildMenu と完全一致する（順序・文言の厳密照合）。
    func test_build_fullTitleSequence_matchesPreSplitRebuildMenu() {
        // Given: 固定スナップショットと固定 now
        let snap = fixedSnapshot()
        let now = cal.date(2026, 5, 27, 12, 0)

        // When: build の title 列を取り出す（separator は "<sep>" として表す）
        let specs = MenuModel().build(snapshot: snap, catalog: catalog, timing: timing, now: now, calendar: cal)
        let seq = specs.map { $0.kind == .separator ? "<sep>" : $0.title }

        // Then: 分割前の rebuildMenu が出していた表示順・文言と完全一致する
        let expected = [
            "Mac Health Keeper", "<sep>",
            "  稼働時間:       1日 2時間",
            "  負荷平均(1分):  1.23",
            "  空きメモリ:     78%",
            "  圧縮メモリ:     1.0 GB",
            "  スワップ使用:   512.00M",
            "  Docker:         停止中",
            "  最終更新: 12:00:00  (⌘R で更新)", "<sep>",
            "クイック対処",
            "🌀 重いアプリを今すぐリフレッシュ",
            "🧹 ファイルキャッシュ解放 (sudo purge)",
            "📉 メモリ圧迫テスト (解放を促す)",
            "🐳 Docker Desktop を Quit", "<sep>",
            "ジョブ（クリックで ON/OFF を切替）",
            "🟢  メモリ／負荷監視    5分毎 ・ 最終 3分前",
            "⚪  Dockerアイドル監視    10分毎",
            "🟢  長期稼働の通知    毎日 9:00 ・ 次回 12/25 09:00",
            "⚪  アプリ自動再起動    毎日 3:00", "<sep>",
            "今すぐ実行",
            "  ▶ メモリ／負荷監視",
            "  ▶ Dockerアイドル監視",
            "  ▶ 長期稼働の通知",
            "  ▶ アプリ自動再起動", "<sep>",
            "通知履歴を開く",
            "監視ログを開く",
            "通知テスト", "<sep>",
            "全ジョブを停止",
            "全ジョブを再開", "<sep>",
            "📚 各指標の意味…",
            "このアプリについて…",
            "Mac Health を終了",
        ]
        XCTAssertEqual(seq, expected)
    }

    /// シナリオ: 未取得時は「取得中…」行になり「最終更新」行が出ない（境界）。
    func test_build_whenNotUpdated_showsLoadingRow() {
        // Given: lastUpdated が distantPast のスナップショット（既定）
        let snap = MetricsSnapshot()
        let now = cal.date(2026, 5, 27, 12, 0)

        // When: build を呼ぶ
        let specs = MenuModel().build(snapshot: snap, catalog: catalog, timing: timing, now: now, calendar: cal)

        // Then: 「取得中…」行があり、refreshNow（最終更新）行は無い
        XCTAssertTrue(specs.contains { $0.title == "  取得中…" && $0.kind == .disabled })
        XCTAssertFalse(specs.contains { $0.action == .refreshNow })
    }

    // MARK: - 警告バナー（issue: 20260529_083530_メトリクス非表示修正）
    //
    // ユースケース: MetricsCollector が metrics.sh 不在を検知したら、
    //               MenuModel が collectorErrors を読み取りメニュー上に警告バナーを挿入する。
    //               対応: .workflow/close/20260529_083530_メトリクス非表示修正/01_要件定義.md
    //               （MenuModelTests のクラス doc のユースケースに対する追補グループ）。

    /// シナリオ: collectorErrors が空ならば警告バナーは挿入されない（既存メニュー出力と等価）。
    func test_build_noCollectorErrors_omitsBanner() {
        // Given: collectorErrors を含まない既定スナップショット
        let snap = MetricsSnapshot()
        let now = cal.date(2026, 5, 27, 12, 0)

        // When: build を呼ぶ
        let specs = MenuModel().build(snapshot: snap, catalog: catalog, timing: timing, now: now, calendar: cal)

        // Then: 警告バナーの文言を含む項目は存在しない
        XCTAssertFalse(specs.contains { $0.title.contains("メトリクス取得不可") })
    }

    /// シナリオ: collectorErrors が 1 件以上あれば、ヘッダー直後（index 2/3）に警告バナーが入る。
    func test_build_withCollectorErrors_insertsBannerAfterHeader() {
        // Given: collectorErrors を 1 件持つスナップショット
        var snap = MetricsSnapshot()
        snap.collectorErrors = ["metrics.sh not found: /path/to/missing"]
        let now = cal.date(2026, 5, 27, 12, 0)

        // When: build を呼ぶ
        let specs = MenuModel().build(snapshot: snap, catalog: catalog, timing: timing, now: now, calendar: cal)

        // Then: headerSpecs（タイトル + セパレータ）の直後に警告ラベル + セパレータが挿入される
        XCTAssertEqual(specs[0].title, "Mac Health Keeper")
        XCTAssertEqual(specs[0].kind, .disabled)
        XCTAssertEqual(specs[1].kind, .separator)
        XCTAssertEqual(specs[2].title, "⚠ メトリクス取得不可: ./install.sh を再実行してください")
        XCTAssertEqual(specs[2].kind, .disabled)
        XCTAssertEqual(specs[3].kind, .separator)
        // And: 既存のメトリクス行も後続で維持される
        XCTAssertTrue(specs.map { $0.title }.contains("  稼働時間:       0日 0時間"))
    }

    /// シナリオ: errorBannerSpecs ヘルパは空配列で空、非空で 2 件を返す（純粋関数の単体）。
    func test_errorBannerSpecs_pureFunction_returnsExpected() {
        // Given: MenuModel インスタンス
        let model = MenuModel()

        // When: errors が空
        let empty = model.errorBannerSpecs([])
        // Then: 空配列
        XCTAssertEqual(empty.count, 0)

        // When: errors が 1 件
        let some = model.errorBannerSpecs(["err"])
        // Then: 警告ラベル + セパレータの 2 件
        XCTAssertEqual(some.count, 2)
        XCTAssertEqual(some[0].title, "⚠ メトリクス取得不可: ./install.sh を再実行してください")
        XCTAssertEqual(some[1].kind, .separator)
    }
}
