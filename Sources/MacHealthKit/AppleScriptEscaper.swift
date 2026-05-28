// Mac Health Keeper - AppleScriptEscaper（Domain/Util・純粋関数）
//
// サブ F・02 §3.2 / §8.2。通知メッセージ等の特殊文字（"・\・改行）を AppleScript ソースへ
// 裸で混入させないための純粋関数群。起動（ShellRunner）と整形（本型）を分離する（単一責務）。
//
// 採用案 A（argv 渡し・推奨）: osascript の `on run argv` でメッセージ/タイトルを argv 参照させ、
//   メッセージはシェルにも AppleScript リテラルにも展開されず、引数要素としてのみ渡る。
//   これにより "・\・改行を含んでも壊れず注入もされない（UC2）。通知タイトル・文言は不変。
//
// 案 B（escapeForAppleScriptLiteral）: argv 渡しが困難な場合のフォールバック用エスケープ。
//   本サブでは notify は案 A を採用するため通常使用しないが、徹底エスケープが必要な箇所のために
//   純粋関数として提供し XCTest で検証可能にする。
// 外部コマンド・AppKit に依存しない（テスト対象）。

import Foundation

public struct AppleScriptEscaper {

    public init() {}

    /// 案 A: 通知用に osascript を argv 渡しで起動するための (executable, args) を返す。
    /// AppleScript 本体（-e のスクリプト）には message/title を **補間しない**。argv で参照する。
    /// 通知タイトルは呼び出し元が "Mac Health" を渡す（文言不変）。
    public func notificationArgs(message: String, title: String) -> (executable: String, args: [String]) {
        // on run argv: item 1 = message, item 2 = title。生メッセージはスクリプト本体に混入しない。
        let script = "on run argv\n"
            + "display notification (item 1 of argv) with title (item 2 of argv)\n"
            + "end run"
        return ("/usr/bin/osascript", ["-e", script, message, title])
    }

    /// 案 B: AppleScript 文字列リテラルとして安全な表現へエスケープする（`\`→`\\`、`"`→`\"`、改行→`\n` の順）。
    /// 補間を残さざるを得ない箇所のためのフォールバック（02 §8.3）。純粋・全入力で全域。
    public func escapeForAppleScriptLiteral(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        out = out.replacingOccurrences(of: "\n", with: "\\n")
        return out
    }
}
