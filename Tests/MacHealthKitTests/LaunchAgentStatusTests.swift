// Mac Health Keeper - LaunchAgentStatus（pure 値型 + パース関数）の XCTest
//
// issue: 20260529_122242_LaunchAgentロード失敗調査と修正
//
// `Sources/MacHealthKit/LaunchAgentStatus.swift` の判定ロジックを XCTest 経路でもカバーする。
// 同じ観点は Sources/MacHealthCheck/main.swift の pure-core ランナーでも実行されるため
// （`make check` 必須経路）、XCTest 非搭載環境（Command Line Tools のみ）でも回帰検知できる。
// 本ファイルは XCTest が使える Xcode 環境向けの追加カバレッジ。
//
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。

import XCTest
@testable import MacHealthKit

/// ユースケース:
/// LaunchAgentStatus.parse が `launchctl print` の出力テキストから状態（notFound /
/// running / notRunning / unknown）を決定し、isLoaded プロパティを正しく返す。
final class LaunchAgentStatusTests: XCTestCase {

    /// シナリオ: "Could not find service" を含む出力は notFound・isLoaded=false（01 UC6-S1）。
    func test_parse_couldNotFind_returnsNotFound() {
        // Given: launchctl print の典型エラー出力
        let printOutput = """
        Bad request.
        Could not find service "com.example.x" in domain for user gui: 501
        """

        // When: parse を呼ぶ
        let s = LaunchAgentStatus.parse(label: "com.example.x", printOutput: printOutput)

        // Then: notFound と判定、isLoaded=false
        XCTAssertEqual(s.status, .notFound)
        XCTAssertFalse(s.isLoaded)
    }

    /// シナリオ: "state = running" を含む出力は running・isLoaded=true（01 UC6-S2）。
    func test_parse_running_returnsRunning() {
        // Given: state = running を含む通常出力
        let printOutput = "gui/501/com.example.r = { state = running active count = 1 }"

        // When: parse を呼ぶ
        let s = LaunchAgentStatus.parse(label: "com.example.r", printOutput: printOutput)

        // Then: running と判定、isLoaded=true
        XCTAssertEqual(s.status, .running)
        XCTAssertTrue(s.isLoaded)
    }

    /// シナリオ: "state = not running" を含む出力は notRunning・isLoaded=true（loaded 扱い・01 UC6-S3）。
    func test_parse_notRunning_returnsNotRunningButLoaded() {
        // Given: state = not running を含む通常出力（次回スケジュール待ち）
        let printOutput = "gui/501/com.example.n = { state = not running runs = 0 }"

        // When: parse を呼ぶ
        let s = LaunchAgentStatus.parse(label: "com.example.n", printOutput: printOutput)

        // Then: notRunning と判定、isLoaded=true（waiting for next schedule は loaded 扱い）
        XCTAssertEqual(s.status, .notRunning)
        XCTAssertTrue(s.isLoaded)
    }

    /// シナリオ: 空文字列は unknown・isLoaded=false（誤って loaded 判定しない）。
    func test_parse_emptyString_returnsUnknown() {
        // Given: 空文字列入力（コーナーケース）
        let printOutput = ""

        // When: parse を呼ぶ
        let s = LaunchAgentStatus.parse(label: "com.example.empty", printOutput: printOutput)

        // Then: unknown 判定、isLoaded=false（安全方向）
        XCTAssertEqual(s.status, .unknown)
        XCTAssertFalse(s.isLoaded)
        // And (Then): 抜粋も空文字（情報の捏造をしない）
        XCTAssertEqual(s.printOutputExcerpt, "")
    }

    /// シナリオ: "Could not find" と "state = running" が同居しても notFound を優先（false positive 回避）。
    func test_parse_conflictingKeywords_prefersNotFound() {
        // Given: ありえないが両キーワードが含まれる出力
        let printOutput = "Could not find service \"x\" ... state = running"

        // When: parse を呼ぶ
        let s = LaunchAgentStatus.parse(label: "com.example.weird", printOutput: printOutput)

        // Then: notFound を優先する（loaded を誤判定しない安全方向）
        XCTAssertEqual(s.status, .notFound)
        XCTAssertFalse(s.isLoaded)
    }
}

/// ユースケース:
/// LaunchAgentStatusSummary が複数 LaunchAgent の load 状態を集計し、
/// 「N/M loaded (NG: x, y)」形式の人間可読サマリ・件数判定を生成する。
final class LaunchAgentStatusSummaryTests: XCTestCase {

    /// シナリオ: 全件 loaded（running と notRunning 混在）なら "N/N loaded"。
    func test_summary_allLoaded_returnsCleanSummary() {
        // Given: 4 件すべて loaded
        let arr = [
            LaunchAgentStatus(label: "com.example.a", status: .running,    printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.example.b", status: .notRunning, printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.example.c", status: .running,    printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.example.d", status: .notRunning, printOutputExcerpt: ""),
        ]

        // When: summaryLine / allLoaded / failedCount を呼ぶ
        let line = LaunchAgentStatusSummary.summaryLine(arr)
        let all = LaunchAgentStatusSummary.allLoaded(arr)
        let failed = LaunchAgentStatusSummary.failedCount(arr)

        // Then: 全件 loaded サマリ、allLoaded=true、failedCount=0
        XCTAssertEqual(line, "4/4 loaded")
        XCTAssertTrue(all)
        XCTAssertEqual(failed, 0)
    }

    /// シナリオ: 1 件 NG（docker）のとき末尾セグメントが NG リストに出る。
    func test_summary_oneFailed_includesShortNameInNGList() {
        // Given: 1 件 notFound（docker）+ 3 件 loaded
        let arr = [
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.monitor", status: .notRunning, printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.docker",  status: .notFound,   printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.uptime",  status: .notRunning, printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.refresh", status: .running,    printOutputExcerpt: ""),
        ]

        // When: summaryLine を呼ぶ
        let line = LaunchAgentStatusSummary.summaryLine(arr)

        // Then: 末尾セグメント "docker" が NG リストに出る
        XCTAssertEqual(line, "3/4 loaded (NG: docker)")
        // And (Then): allLoaded=false, failedCount=1
        XCTAssertFalse(LaunchAgentStatusSummary.allLoaded(arr))
        XCTAssertEqual(LaunchAgentStatusSummary.failedCount(arr), 1)
    }

    /// シナリオ: 空配列に対する allLoaded は false（vacuous-true を避ける）。
    func test_summary_emptyArray_allLoadedReturnsFalse() {
        // Given: 空の状態配列
        let arr: [LaunchAgentStatus] = []

        // When: allLoaded / summaryLine を呼ぶ
        let all = LaunchAgentStatusSummary.allLoaded(arr)
        let line = LaunchAgentStatusSummary.summaryLine(arr)

        // Then: allLoaded=false（偽の安心感を与えない）、summary は "0/0 loaded"
        XCTAssertFalse(all)
        XCTAssertEqual(line, "0/0 loaded")
    }
}
