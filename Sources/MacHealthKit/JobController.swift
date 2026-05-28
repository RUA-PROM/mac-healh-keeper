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

    /// launchctl list | grep <label> の trim 結果が非空なら true（現 L159-160 / L440-441 と同一）。
    /// load/unload を呼ばない（read-only）。
    public func isLoaded(job: String) -> Bool {
        let label = catalog.label(for: job)
        let out = run("launchctl list 2>/dev/null | grep '\(label)'")
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Command（状態変更）

    /// ジョブを起動する（現 L436: bootstrap、フォールバック launchctl load）。
    @discardableResult
    public func load(job: String) -> String {
        let label = catalog.label(for: job)
        let plist = "\(launchAgentDir)/\(label).plist"
        return run("launchctl bootstrap gui/\(uid) '\(plist)' 2>&1 || launchctl load '\(plist)' 2>&1")
    }

    /// ジョブを停止する（現 L434: bootout、フォールバック launchctl unload）。
    @discardableResult
    public func unload(job: String) -> String {
        let label = catalog.label(for: job)
        let plist = "\(launchAgentDir)/\(label).plist"
        return run("launchctl bootout gui/\(uid)/\(label) 2>&1 || launchctl unload '\(plist)' 2>&1")
    }

    /// wasLoaded に応じて load/unload を選ぶ（現 L433-437 と同一の分岐）。
    @discardableResult
    public func toggle(job: String, wasLoaded: Bool) -> String {
        return wasLoaded ? unload(job: job) : load(job: job)
    }

    /// 全ジョブを再開（現 resumeAllJobs L495: `mac-health enable`）。
    @discardableResult
    public func enableAll() -> String {
        return run("'\(cliPath)' enable")
    }

    /// 全ジョブを停止（現 pauseAllJobs L480: `mac-health disable`）。
    @discardableResult
    public func disableAll() -> String {
        return run("'\(cliPath)' disable")
    }

    // MARK: - 内部

    /// 既存コマンド文字列をそのまま zsh -l -c で実行する（現 shell(_:) 互換）。
    @discardableResult
    private func run(_ cmd: String) -> String {
        return runner.run("/bin/zsh", ["-l", "-c", cmd])
    }
}
