// Mac Health Keeper - MetricsCollector（Imperative Shell）
//
// 現 src/MacHealth.swift gatherMetrics() L115-187 の実コマンド実行部を切り出したもの。
// ShellRunner で実コマンドを実行し、出力を MetricsParser に委譲して MetricsSnapshot を組み立てる。
// ジョブの loaded 判定は JobController.isLoaded(query) を再利用する（収集経路と toggle 経路で共有）。
// 実コマンド・FileManager 依存のため XCTest 対象外（02 §6.1）。算出部は MetricsParser でカバー。
//
// コマンド文字列・順序・フォールバックは現状の gatherMetrics と完全一致させる（振る舞い不変）。

// 注: swiftc ビルドでは src/ と Sources/MacHealthKit/ を 1 モジュールとしてまとめてコンパイルするため
// import MacHealthKit は不要（型は同一モジュール内で解決される）。
import Foundation

final class MetricsCollector {
    private let runner: ShellRunner
    private let parser: MetricsParser
    private let catalog: JobCatalog
    private let jobController: JobController
    private let timing: ScheduleTiming
    private let logDir: String

    init(runner: ShellRunner,
         parser: MetricsParser,
         catalog: JobCatalog,
         jobController: JobController,
         timing: ScheduleTiming,
         logDir: String) {
        self.runner = runner
        self.parser = parser
        self.catalog = catalog
        self.jobController = jobController
        self.timing = timing
        self.logDir = logDir
    }

    /// 既存コマンド文字列をそのまま zsh -l -c で実行する（現 shell(_:) 互換）。
    private func shell(_ cmd: String) -> String {
        return runner.run("/bin/zsh", ["-l", "-c", cmd])
    }

    /// 現 gatherMetrics() と同一のコマンド・順序で収集し MetricsSnapshot を組み立てる。
    func collect() -> MetricsSnapshot {
        var s = MetricsSnapshot()

        let load = shell("uptime | sed -E 's/.*load averages?:?[[:space:]]+([0-9.]+).*/\\1/'")
        s.loadAvg = parser.parseLoadAvg(load)

        let swap = shell("sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+M).*/\\1/'")
        s.swapUsed = parser.parseSwapUsed(swap)

        let memFree = shell("memory_pressure 2>/dev/null | awk -F': ' '/memory free percentage/ {gsub(\"%\",\"\",$2); print $2}'")
        s.memoryFreePct = parser.parseMemoryFreePct(memFree)

        let bootStr = shell("sysctl -n kern.boottime | awk '{print $4}' | tr -d ','")
        let now = Int(Date().timeIntervalSince1970)
        let uptime = parser.uptimeDaysHours(bootString: bootStr, nowEpoch: now)
        s.uptimeDays = uptime.days
        s.uptimeHours = uptime.hours

        let compPagesStr = shell("vm_stat | awk '/Pages occupied by compressor/ {gsub(\"\\\\.\",\"\"); print $5}'")
        s.compressedGB = parser.compressedGB(pages: compPagesStr)

        let dockerRunning = shell("pgrep -f 'com\\.apple\\.Virtualization\\.VirtualMachine' >/dev/null && echo 1 || echo 0")
            .trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        if dockerRunning {
            let count = shell("(docker ps -q 2>/dev/null | wc -l | tr -d ' ') & p=$!; (sleep 3; kill -9 $p 2>/dev/null) >/dev/null 2>&1 & wait $p 2>/dev/null")
            s.dockerLine = parser.dockerLine(running: true, containerCount: count)
        } else {
            s.dockerLine = parser.dockerLine(running: false, containerCount: "")
        }

        // 各ジョブの情報を収集
        for job in catalog.jobs {
            var status = JobStatus()
            status.loaded = jobController.isLoaded(job: job)

            // ログファイルの mtime を「最終実行」として使う
            let logPath = "\(logDir)/\(job).log"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
               let mtime = attrs[.modificationDate] as? Date {
                status.lastRun = mtime
            }

            // 次回実行時刻
            if let schedule = catalog.schedules[job] {
                switch schedule {
                case .interval(let sec):
                    if let last = status.lastRun {
                        status.nextRun = last.addingTimeInterval(TimeInterval(sec))
                    }
                case .daily(let h, let m):
                    status.nextRun = timing.nextDailyRun(hour: h, minute: m, now: Date(), calendar: Calendar.current)
                }
            }

            s.jobs[job] = status
        }

        s.lastUpdated = Date()
        return s
    }
}
