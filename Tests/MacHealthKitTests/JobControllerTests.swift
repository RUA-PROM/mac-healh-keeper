// Mac Health Keeper - JobController（CQRS）の単体テスト（T5）
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
// 01 UC1-S2 / UC2-S1 と 03 §2.5.4 のテスト仕様に 1 対 1 対応する。

import XCTest
@testable import MacHealthKit

/// ユースケース: ジョブ ON/OFF を CQRS（command/query 分離）で扱い、query に副作用が無いこと。
final class JobControllerTests: XCTestCase {

    private func makeController(spy: SpyShellRunner) -> JobController {
        return JobController(runner: spy,
                             catalog: JobCatalog(),
                             uid: "501",
                             launchAgentDir: "/tmp/la",
                             cliPath: "/tmp/mac-health")
    }

    /// シナリオ: 状態取得 query を 2 回呼んでも load/unload は発行されない（01 UC1-S2）。
    func test_isLoaded_calledTwice_hasNoSideEffect() {
        // Given: loaded を表す list 出力を返すスタブと JobController
        let spy = SpyShellRunner(stubbed: [
            "com.github.adachi-tatsuru.machealth.monitor\t0\t-",
            "com.github.adachi-tatsuru.machealth.monitor\t0\t-",
        ])
        let controller = makeController(spy: spy)

        // When: query を 2 回呼ぶ
        _ = controller.isLoaded(job: "monitor")
        // And (When): もう一度 query を呼ぶ
        _ = controller.isLoaded(job: "monitor")

        // Then: 発行コマンドはすべて launchctl list 系（引数配列 ["list"]）で、load/unload は 0 回
        XCTAssertTrue(spy.calls.allSatisfy { $0.executable == "/bin/launchctl" && $0.args == ["list"] })
        let joinedArgs = spy.calls.map { $0.args.joined(separator: " ") }.joined(separator: "\n")
        XCTAssertFalse(joinedArgs.contains("bootstrap"))
        XCTAssertFalse(joinedArgs.contains("bootout"))
        XCTAssertFalse(joinedArgs.contains("load"))
        XCTAssertEqual(spy.calls.count, 2)
    }

    /// シナリオ: unloaded から toggle すると、その後の query で loaded になる（01 UC2-S1）。
    func test_toggle_fromUnloaded_thenQueryReturnsLoaded() {
        // Given: toggle(load) の結果と、後続 isLoaded が loaded を返すスタブ
        let spy = SpyShellRunner(stubbedSequence: [
            "",                                                   // toggle(load) の結果
            "com.github.adachi-tatsuru.machealth.monitor\t0\t-",  // 後続 isLoaded → loaded
        ])
        let controller = makeController(spy: spy)

        // When: unloaded 状態から toggle（command）を実行する
        _ = controller.toggle(job: "monitor", wasLoaded: false)
        // And (When): その後 query する
        let loaded = controller.isLoaded(job: "monitor")

        // Then: load 系コマンド（bootstrap or load）が引数配列で発行され、query は loaded を返す
        let joinedArgs = spy.calls.map { $0.args.joined(separator: " ") }.joined(separator: "\n")
        XCTAssertTrue(joinedArgs.contains("bootstrap") || joinedArgs.contains("load"))
        XCTAssertTrue(spy.calls.allSatisfy { $0.executable == "/bin/launchctl" })
        XCTAssertTrue(loaded)
    }

    /// シナリオ: list 出力が空ならジョブは unloaded、ラベルを含めば loaded（境界）。
    func test_isLoaded_emptyVsLabelOutput() {
        // Given: 空出力を返すスタブ
        let emptySpy = SpyShellRunner(stubbed: [""])
        // And (Given): ラベルを含む出力を返すスタブ
        let labelSpy = SpyShellRunner(stubbed: ["com.github.adachi-tatsuru.machealth.docker\t0\t-"])

        // When: それぞれ isLoaded を呼ぶ
        let unloaded = makeController(spy: emptySpy).isLoaded(job: "docker")
        let loaded = makeController(spy: labelSpy).isLoaded(job: "docker")

        // Then: 空は false、ラベル含みは true
        XCTAssertFalse(unloaded)
        XCTAssertTrue(loaded)
    }
}
