// Mac Health Keeper - JobController 注入耐性（launchctl 安全化）の単体テスト（サブ F・T3）
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
// 01 UC3-S1 / 03 §2.3.4 のテスト仕様に対応する。SpyShellRunner で launchctl 出力をスタブする（決定的）。

import XCTest
@testable import MacHealthKit

/// ユースケース: JobController が label をシェル補間せず引数/フィルタで安全にジョブ状態を取得・操作する。
final class JobControllerSafetyTests: XCTestCase {

    private func makeController(spy: SpyShellRunner) -> JobController {
        return JobController(runner: spy,
                             catalog: JobCatalog(),
                             uid: "501",
                             launchAgentDir: "/tmp",
                             cliPath: "/tmp/mac-health")
    }

    /// シナリオ: isLoaded が ["list"] で起動し label を補間せず従来同値の真偽を返す（01 UC3-S1）。
    func test_isLoaded_runsListWithoutInterpolatingLabel_resultMatchesGrep() {
        // Given: 当該 label を含む launchctl list 出力を返すスタブと JobController
        let label = JobCatalog().label(for: "monitor") // com.github.adachi-tatsuru.machealth.monitor
        let spy = SpyShellRunner(stubbed: ["123\t0\t\(label)\n456\t0\tother\n"])
        let sut = makeController(spy: spy)

        // When: isLoaded を呼ぶ
        let loaded = sut.isLoaded(job: "monitor")

        // Then: 従来 grep 非空判定と同値 true で、launchctl は ["list"] のみ・label は補間されない
        XCTAssertTrue(loaded)
        XCTAssertEqual(spy.calls.last?.executable, "/bin/launchctl")
        XCTAssertEqual(spy.calls.last?.args, ["list"])
        // And (Then): label が引数のどの要素にも補間されていない
        XCTAssertFalse(spy.calls.last?.args.contains(where: { $0.contains(label) }) ?? false,
                       "label が引数に補間されている")
    }

    /// シナリオ: list 出力に label を含む行が無ければ isLoaded は false（従来 grep 非空判定と同値）。
    func test_isLoaded_whenLabelAbsent_returnsFalse() {
        // Given: 当該 label を含まない launchctl list 出力を返すスタブ
        let spy = SpyShellRunner(stubbed: ["123\t0\tother.service\n"])
        let sut = makeController(spy: spy)

        // When: isLoaded を呼ぶ
        let loaded = sut.isLoaded(job: "monitor")

        // Then: false を返し、起動は ["list"] のみ
        XCTAssertFalse(loaded)
        XCTAssertEqual(spy.calls.last?.args, ["list"])
    }

    /// シナリオ: load が bootstrap を引数配列で起動し plist/uid/label を引数要素として渡す（シェル補間しない）。
    func test_load_invokesBootstrapAsArgumentArray_withoutShellInterpolation() {
        // Given: bootstrap が成功（空出力）を返すスタブ
        let spy = SpyShellRunner(stubbed: [""])
        let sut = makeController(spy: spy)

        // When: load を呼ぶ
        _ = sut.load(job: "monitor")

        // Then: launchctl を実行ファイルに bootstrap・gui/<uid>・plist が独立引数として渡る
        let label = JobCatalog().label(for: "monitor")
        XCTAssertEqual(spy.calls.last?.executable, "/bin/launchctl")
        XCTAssertEqual(spy.calls.last?.args, ["bootstrap", "gui/501", "/tmp/\(label).plist"])
        // And (Then): `||` や `2>&1` 等のシェル制御文字が引数要素に含まれない（シェルへ渡らない）
        let joined = spy.calls.last?.args.joined(separator: " ") ?? ""
        XCTAssertFalse(joined.contains("||"))
        XCTAssertFalse(joined.contains("2>&1"))
    }

    /// シナリオ: bootstrap がエラー出力を返したとき Swift 側で二次コマンド（load）にフォールバックする（現 `||` 等価）。
    func test_load_whenBootstrapFails_fallsBackToLoad() {
        // Given: bootstrap がエラー出力を返すスタブ
        let spy = SpyShellRunner(stubbed: ["Bootstrap failed: 5: Input/output error"])
        let sut = makeController(spy: spy)

        // When: load を呼ぶ
        _ = sut.load(job: "monitor")

        // Then: 1 回目 bootstrap、2 回目に load へフォールバックし、いずれも launchctl の引数配列起動
        let label = JobCatalog().label(for: "monitor")
        XCTAssertEqual(spy.calls.count, 2)
        XCTAssertEqual(spy.calls[0].args.first, "bootstrap")
        XCTAssertEqual(spy.calls[1].executable, "/bin/launchctl")
        XCTAssertEqual(spy.calls[1].args, ["load", "/tmp/\(label).plist"])
    }

    /// シナリオ: enableAll/disableAll が CLI を引数配列で起動する（補間文字列でなく配列）。
    func test_enableAll_disableAll_invokeCliAsArgumentArray() {
        // Given: スパイ runner と JobController
        let spy = SpyShellRunner()
        let sut = makeController(spy: spy)

        // When: enableAll と disableAll を呼ぶ
        _ = sut.enableAll()
        _ = sut.disableAll()

        // Then: cliPath を実行ファイルに ["enable"]/["disable"] が引数として渡る
        XCTAssertEqual(spy.calls[0].executable, "/tmp/mac-health")
        XCTAssertEqual(spy.calls[0].args, ["enable"])
        XCTAssertEqual(spy.calls[1].executable, "/tmp/mac-health")
        XCTAssertEqual(spy.calls[1].args, ["disable"])
    }
}
