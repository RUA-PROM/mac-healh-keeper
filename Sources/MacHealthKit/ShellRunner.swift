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

/// 既定実装。当面は現状の `zsh -l -c <文字列>` 実行をラップする。
/// 呼び出し側は run("/bin/zsh", ["-l", "-c", cmd]) として既存のコマンド文字列をそのまま渡す。
/// F が run の実装を executable + args の直接実行へ差し替えても呼び出し側を変えずに済む境界。
public final class ZshShellRunner: ShellRunner {

    public init() {}

    /// 現 shell(_:) L597-613 と同一挙動: Process で実行、throw 時 ""、stderr 破棄。
    @discardableResult
    public func run(_ executable: String, _ args: [String]) -> String {
        let task = Process()
        task.launchPath = executable
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
