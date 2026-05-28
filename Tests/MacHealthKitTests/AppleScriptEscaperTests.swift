// Mac Health Keeper - AppleScriptEscaper の単体テスト（サブ F・T2）
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
// 01 UC2-S1 / 03 §2.2.4 のテスト仕様に対応する。純粋関数のため網羅容易（実プロセス不要）。

import XCTest
@testable import MacHealthKit

/// ユースケース: 通知メッセージの特殊文字を安全に扱い AppleScript への注入・破損を防ぐ。
final class AppleScriptEscaperTests: XCTestCase {

    /// シナリオ: `"` と `\` と改行を含むメッセージで安全な引数列を生成する（01 UC2-S1）。
    func test_notificationArgs_withQuotesBackslashNewline_isSafe() {
        // Given: ダブルクォート・バックスラッシュ・改行を含む通知メッセージと固定タイトル
        let escaper = AppleScriptEscaper()
        let message = "a\"b\\c\nd"

        // When: notify 用の (executable, args) を生成する
        let r = escaper.notificationArgs(message: message, title: "Mac Health")

        // Then: osascript を実行ファイルとし、メッセージ・タイトルは独立引数として渡る（AppleScript ソースに混入しない）
        XCTAssertEqual(r.executable, "/usr/bin/osascript")
        XCTAssertTrue(r.args.contains(message), "メッセージが引数要素として渡らずソースに補間されている")
        XCTAssertTrue(r.args.contains("Mac Health"), "タイトルが引数要素として渡っていない")
        // And (Then): -e で渡すスクリプト部分には生メッセージが含まれない（注入面なし・裸の " が混入しない）
        let scriptPart = r.args.first(where: { $0.contains("display notification") }) ?? ""
        XCTAssertFalse(scriptPart.contains(message), "スクリプト本体にメッセージが補間されている")
        XCTAssertTrue(scriptPart.contains("item 1 of argv"), "argv 参照スクリプトになっていない")
    }

    /// シナリオ: 空メッセージでも安全に引数列を生成する（境界・空文字）。
    func test_notificationArgs_withEmptyMessage_isSafe() {
        // Given: 空のメッセージ
        let escaper = AppleScriptEscaper()
        let message = ""

        // When: notify 用の引数列を生成する
        let r = escaper.notificationArgs(message: message, title: "Mac Health")

        // Then: 実行ファイルは osascript で、空メッセージが引数要素として渡る
        XCTAssertEqual(r.executable, "/usr/bin/osascript")
        XCTAssertEqual(r.args.last(where: { $0 == "Mac Health" }), "Mac Health")
        XCTAssertTrue(r.args.contains(""), "空メッセージが引数要素として渡っていない")
    }

    /// シナリオ: 案 B のリテラルエスケープが `\`→`\\`、`"`→`\"`、改行→`\n` の順で安全表現を返す（フォールバック）。
    func test_escapeForAppleScriptLiteral_escapesBackslashQuoteNewline() {
        // Given: バックスラッシュ・ダブルクォート・改行を含む文字列
        let escaper = AppleScriptEscaper()
        let raw = "a\"b\\c\nd"

        // When: AppleScript リテラル用にエスケープする
        let escaped = escaper.escapeForAppleScriptLiteral(raw)

        // Then: \ は \\、" は \"、改行は \n に変換され、裸の " や生改行が残らない
        XCTAssertEqual(escaped, "a\\\"b\\\\c\\nd")
        XCTAssertFalse(escaped.contains("\n"), "生改行が残っている")
    }
}
