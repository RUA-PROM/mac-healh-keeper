// Mac Health Keeper - ShellRunner（Infra・外部コマンド実行の I/F）
//
// 現 src/MacHealth.swift shell(_:) L597-613 を Infra へ切り出したもの。
// サブ F が「引数配列化・注入耐性」を寄せられるよう、実行ファイル＋引数配列を受ける I/F を確定する。
// 本サブは I/F 確定とラップに留め、注入対策の実装はサブ F に委譲する（02 §3.3 / §8.2）。
//
// テスト容易性のため protocol は MacHealthKit（AppKit 非依存）に置き、JobController から参照する。
// 既定実装 ZshShellRunner は Process（Foundation のみ）を使うため同居できるが、実プロセス実行は
// テスト対象外（02 §6.1）。

import Foundation

public protocol ShellRunner {
    /// 実行ファイルと引数配列を受け、標準出力（UTF-8）を返す。失敗時は "" を返す（現状互換）。
    @discardableResult
    func run(_ executable: String, _ args: [String]) -> String
}

/// 既定実装（サブ F・02 §3.1 / §8.2）。
/// `Process.executableURL` + `arguments` で **引数配列のまま** 外部コマンドを直接起動する。
/// 各 args 要素はシェルのトークン分割・展開（`;`・`$()`・`&&`・`||`）を経ずに渡るため、
/// `; rm -rf x` や `$(touch y)` を含む引数は単一引数として扱われ、追加コマンドは実行されない（UC1）。
/// I/F（実行ファイル＋引数配列）と stdout の取り回し（trim は呼び出し元）は不変。
public final class ZshShellRunner: ShellRunner {

    public init() {}

    /// executable + args を引数配列のまま直接起動し stdout（UTF-8）を返す。throw 時 ""、stderr 破棄（現状互換）。
    @discardableResult
    public func run(_ executable: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
