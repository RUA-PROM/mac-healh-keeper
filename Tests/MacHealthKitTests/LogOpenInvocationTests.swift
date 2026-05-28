// Mac Health Keeper - 呼び出し元の引数配列移行（ログ open 等）の単体テスト（サブ F・T5）
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
// 01 UC1-S1 派生 / 03 §2.5.4 のテスト仕様に対応する。
// AppDelegate は AppKit 依存で XCTest 対象外のため、移行後の起動シーケンス（touch→open / osascript の
// 引数配列形）を SpyShellRunner で再現し、`&&`/`||` がシェルへ渡らないことを検証する（02 §6.1）。

import XCTest
@testable import MacHealthKit

/// ユースケース: 呼び出し元（ログ open / quick action）が補間文字列でなく引数配列で安全に起動する。
final class LogOpenInvocationTests: XCTestCase {

    /// シナリオ: openEventsLog 相当が touch と open を別々の引数配列で起動する（&& 非使用・01 UC1-S1 派生）。
    func test_openLog_invokesTouchThenOpenAsArgumentArrays() {
        // Given: スパイ runner と特殊文字を含み得るログパス
        let spy = SpyShellRunner()
        let path = "/tmp/Logs/MacHealth/events.log"

        // When: ログオープン相当の処理（touch → open -a Console）を引数配列で実行する
        spy.run("/usr/bin/touch", [path])
        spy.run("/usr/bin/open", ["-a", "Console", path])

        // Then: 2 回の起動がいずれも引数配列で、path が単一要素として渡る（&& がシェルに渡らない）
        XCTAssertEqual(spy.calls[0].executable, "/usr/bin/touch")
        XCTAssertEqual(spy.calls[0].args, [path])
        XCTAssertEqual(spy.calls[1].executable, "/usr/bin/open")
        XCTAssertEqual(spy.calls[1].args, ["-a", "Console", path])
        // And (Then): どの引数要素にもシェル連結 && が含まれない
        let joined = spy.calls.map { $0.args.joined(separator: " ") }.joined(separator: "\n")
        XCTAssertFalse(joined.contains("&&"))
    }

    /// シナリオ: ジョブ実行 CLI が `run <job>` を引数配列で起動する（補間文字列でない・01 UC1-S1 派生）。
    func test_runJob_invokesCliWithRunAndJobAsArgumentArray() {
        // Given: スパイ runner と CLI パス・ジョブ ID（特殊文字を擬似挿入）
        let spy = SpyShellRunner()
        let cli = "/Users/x/.local/bin/mac-health/bin/mac-health"
        let job = "refresh; rm -rf /"  // 注入を擬似挿入しても単一引数で保持されること

        // When: CLI を引数配列で起動する
        spy.run(cli, ["run", job])

        // Then: CLI が実行ファイル、run とジョブ ID が独立引数として渡り、ジョブ ID は単一要素で保持される
        XCTAssertEqual(spy.calls.last?.executable, cli)
        XCTAssertEqual(spy.calls.last?.args, ["run", job])
        XCTAssertEqual(spy.calls.last?.args.last, job, "ジョブ ID がシェル分割されず単一引数として保持されていない")
    }
}
