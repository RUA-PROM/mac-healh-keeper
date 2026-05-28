// Mac Health Keeper - ZshShellRunner 注入耐性の単体テスト（サブ F・T1）
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
// 01 UC1-S1 / 03 §2.1.4 のテスト仕様に対応する。
// 実プロセスを起動するが `printf` を実行ファイルにした決定的検証（02 §6.1）。一時ファイル非生成で注入非実行を実証する。

import XCTest
@testable import MacHealthKit

/// ユースケース: ShellRunner が引数配列を単一引数として渡し、コマンド注入（追加コマンド実行）を防ぐ。
final class ZshShellRunnerInjectionTests: XCTestCase {

    /// シナリオ: `;` を含む注入ペイロードが単一引数になり追加コマンドが実行されない（01 UC1-S1）。
    func test_run_treatsSemicolonPayloadAsSingleArgument_doesNotExecuteExtraCommand() throws {
        // Given: 一時ファイルパスと、それを作ろうとする `; touch` 注入ペイロードを引数に持つ printf 実行
        let tmp = NSTemporaryDirectory() + "f_inject_semicolon_\(UUID().uuidString).flag"
        try? FileManager.default.removeItem(atPath: tmp)
        let payload = "; touch \(tmp)"
        let runner = ZshShellRunner()

        // When: printf に "%s" と payload を引数配列で渡して実行する
        let out = runner.run("/usr/bin/printf", ["%s", payload])

        // Then: payload はそのまま単一引数として出力され、注入された touch は実行されない（一時ファイル非生成）
        XCTAssertEqual(out, payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp), "注入された touch が実行され一時ファイルが生成された")
        try? FileManager.default.removeItem(atPath: tmp)
    }

    /// シナリオ: `$()` を含む注入ペイロードがコマンド置換されず単一引数になる（01 UC1-S1）。
    func test_run_treatsCommandSubstitutionPayloadAsSingleArgument() throws {
        // Given: 一時ファイルパスと、それを作ろうとする `$(touch ...)` 注入ペイロードを引数に持つ printf 実行
        let tmp = NSTemporaryDirectory() + "f_inject_subst_\(UUID().uuidString).flag"
        try? FileManager.default.removeItem(atPath: tmp)
        let payload = "$(touch \(tmp))"
        let runner = ZshShellRunner()

        // When: printf に "%s" と payload を引数配列で渡して実行する
        let out = runner.run("/usr/bin/printf", ["%s", payload])

        // Then: payload は置換されず単一引数として出力され、touch は実行されない（一時ファイル非生成）
        XCTAssertEqual(out, payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp), "コマンド置換 $() が実行され一時ファイルが生成された")
        try? FileManager.default.removeItem(atPath: tmp)
    }

    /// シナリオ: 存在しない実行ファイルパスでは throw を握り "" を返す（異常系・現状互換）。
    func test_run_withMissingExecutable_returnsEmptyString() {
        // Given: 存在しない実行ファイルパス
        let runner = ZshShellRunner()
        let missing = "/no/such/executable_\(UUID().uuidString)"

        // When: run を呼ぶ
        let out = runner.run(missing, ["arg"])

        // Then: 例外を投げず "" を返す
        XCTAssertEqual(out, "")
    }
}
