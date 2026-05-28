// Mac Health Keeper - ShellRunner I/F の単体テスト（T3）
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
// 03 §2.3.4 のテスト仕様に対応する。
// 既定実装 ZshShellRunner の実プロセス実行は XCTest 対象外（実コマンド・環境依存で非決定的。02 §6.1）。

import XCTest
@testable import MacHealthKit

/// ユースケース: ShellRunner の I/F がスタブ可能で、呼び出し引数を検証できる。
final class ShellRunnerContractTests: XCTestCase {

    /// シナリオ: スタブが run の引数を記録し、設定した戻り値を返す。
    func test_spyRunner_recordsArgsAndReturnsStub() {
        // Given: 戻り値 "x" を返す記録用スタブ
        let spy = SpyShellRunner(stubbed: ["x"])

        // When: run を呼ぶ
        let out = spy.run("/bin/zsh", ["-l", "-c", "echo x"])

        // Then: 引数が記録され、戻り値はスタブ値
        XCTAssertEqual(spy.calls.last?.executable, "/bin/zsh")
        XCTAssertEqual(spy.calls.last?.args, ["-l", "-c", "echo x"])
        XCTAssertEqual(out, "x")
    }
}
