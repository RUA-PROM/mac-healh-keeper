// Mac Health Keeper - JobController（Infra・CQRS）
//
// 現 src/MacHealth.swift toggleJob L419-461 / pauseAllJobs L473-486 / resumeAllJobs L488-501 /
// gatherMetrics 内の launchctl list L158-160 に混在していた状態変更（bootout/bootstrap）と
// 状態取得（launchctl list）を、command と query の別メソッドに分離したもの（CQRS）。
//
// command（load/unload/toggle/enableAll/disableAll）は状態を変更する。
// query（isLoaded）は launchctl list を読むだけで状態を変えない（副作用なし・UC1-S2）。
// シェルコマンド文字列は現状と完全一致させ、ShellRunner 経由で実行する。AppKit 非依存。

import Foundation

public final class JobController {
    private let runner: ShellRunner
    private let catalog: JobCatalog
    private let uid: String
    private let launchAgentDir: String
    private let cliPath: String

    public init(runner: ShellRunner,
                catalog: JobCatalog,
                uid: String,
                launchAgentDir: String,
                cliPath: String) {
        self.runner = runner
        self.catalog = catalog
        self.uid = uid
        self.launchAgentDir = launchAgentDir
        self.cliPath = cliPath
    }

    // MARK: - Query（副作用なし）

    /// launchctl list の出力を Swift 側で走査し label を含む非空行があれば true。
    /// 02 §3.3 UC3: label をシェル補間せず引数 ["list"] のみで起動し、判定はリテラル比較で行う
    /// （`grep '<label>'` の文字列補間を排除）。結果は従来の grep 非空判定と同値。load/unload を呼ばない（read-only）。
    public func isLoaded(job: String) -> Bool {
        let label = catalog.label(for: job)
        let out = runner.run("/bin/launchctl", ["list"])
        return out
            .split(separator: "\n", omittingEmptySubsequences: true)
            .contains { $0.contains(label) }
    }

    // MARK: - Command（状態変更）

    /// ジョブを起動する（現 L436: bootstrap、フォールバック launchctl load）。
    /// 02 §3.3: plist/label/uid を引数要素として渡し、`||` フォールバックは Swift 側で run 結果を見て分岐する。
    @discardableResult
    public func load(job: String) -> String {
        let label = catalog.label(for: job)
        let plist = "\(launchAgentDir)/\(label).plist"
        let primary = runner.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist])
        // bootstrap 失敗（出力にエラー）時のフォールバック（現 `|| launchctl load` 相当を Swift 側分岐で）。
        if bootstrapSucceeded(primary) {
            return primary
        }
        return runner.run("/bin/launchctl", ["load", plist])
    }

    /// ジョブを停止する（現 L434: bootout、フォールバック launchctl unload）。
    @discardableResult
    public func unload(job: String) -> String {
        let label = catalog.label(for: job)
        let plist = "\(launchAgentDir)/\(label).plist"
        let primary = runner.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
        if bootstrapSucceeded(primary) {
            return primary
        }
        return runner.run("/bin/launchctl", ["unload", plist])
    }

    /// wasLoaded に応じて load/unload を選ぶ（現 L433-437 と同一の分岐）。
    @discardableResult
    public func toggle(job: String, wasLoaded: Bool) -> String {
        return wasLoaded ? unload(job: job) : load(job: job)
    }

    /// 全ジョブを再開（現 resumeAllJobs L495: `mac-health enable`）。
    @discardableResult
    public func enableAll() -> String {
        return runner.run(cliPath, ["enable"])
    }

    /// 全ジョブを停止（現 pauseAllJobs L480: `mac-health disable`）。
    @discardableResult
    public func disableAll() -> String {
        return runner.run(cliPath, ["disable"])
    }

    // MARK: - 内部

    /// bootstrap/bootout が成功したとみなせるか（出力にエラー兆候が無い）を判定し、
    /// 失敗時のみ二次コマンド（load/unload）へフォールバックする（現 `||` のシェル分岐の等価実装）。
    /// シェルの終了コードに依らず、現状の `2>&1` 出力を Swift 側で観測して分岐する。
    private func bootstrapSucceeded(_ output: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // 成功時は何も出力しないのが通常（現状互換）。
            return true
        }
        // `Bootstrap failed`・`Operation not permitted`・`No such file` などのエラー出力時のみフォールバック。
        let lower = trimmed.lowercased()
        let errorMarkers = ["error", "failed", "not permitted", "no such", "could not", "invalid"]
        return !errorMarkers.contains { lower.contains($0) }
    }
}
