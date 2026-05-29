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
    private let metricsShPath: String
    private let fileExists: (String) -> Bool

    /// metrics.sh 未配置時の stderr 警告を 1 回だけに抑止するためのフラグ。
    /// 60 秒周期の収集でログがスパムにならないようにする。issue: 20260529_083530_メトリクス非表示修正。
    private var warnedAboutMissingScript: Bool = false

    init(runner: ShellRunner,
         parser: MetricsParser,
         catalog: JobCatalog,
         jobController: JobController,
         timing: ScheduleTiming,
         logDir: String,
         metricsShPath: String,
         fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.runner = runner
        self.parser = parser
        self.catalog = catalog
        self.jobController = jobController
        self.timing = timing
        self.logDir = logDir
        self.metricsShPath = metricsShPath
        self.fileExists = fileExists
    }

    /// 02 §3.4: サブ C 集約済みの metrics.sh を `metrics.sh <metric>` の引数呼び出しで起動する。
    /// metric は固定列挙（補間値・ユーザー入力なし）。MetricsParser 入力は現状の sed/awk 抽出後と同値。
    private func metric(_ name: String) -> String {
        return runner.run("/bin/bash", [metricsShPath, name])
    }

    /// 02 §8.3 残置: パイプ前提の固定文字列実行。metrics.sh への寄せが MetricsParser 入力書式の
    /// 不一致（＝振る舞い破壊）を招くため、引数配列＋固定文字列で残置する。**補間値は流入しない**
    /// （すべて固定リテラルのみ・注入面なし）。bootStr の生 boot epoch・compressor 生ページ数・
    /// docker count の 3 秒タイムアウト（& wait）は MetricsParser がそのまま入力として要求するため。
    private func shellFixed(_ cmd: String) -> String {
        return runner.run("/bin/zsh", ["-l", "-c", cmd])
    }

    /// 現 gatherMetrics() と同一の値・順序で収集し MetricsSnapshot を組み立てる（振る舞い不変）。
    func collect() -> MetricsSnapshot {
        var s = MetricsSnapshot()

        // issue 20260529_083530_メトリクス非表示修正:
        // インストール先に metrics.sh が無い場合（古い install.sh 実行のみで lib/ が更新されていない等）、
        // /bin/bash <不在パス> は空文字を返し、MetricsParser のフォールバックで全指標が "—" になり
        // 「サイレント空欄」状態になる。検知 → 伝播 → stderr 警告のロジックは MetricsCollectorPolicy
        // （Functional Core）に切り出してテスト可能にしてある。本 Imperative Shell は I/O のみ担う。
        let decision = MetricsCollectorPolicy.decide(
            exists: fileExists(metricsShPath),
            path: metricsShPath,
            previouslyWarned: warnedAboutMissingScript
        )
        s.collectorErrors.append(contentsOf: decision.collectorErrorsToAppend)
        if let line = decision.stderrLineToWrite {
            fputs(line, stderr)
        }
        warnedAboutMissingScript = decision.nextWarnedAboutMissingScript

        // load/swap/free は metrics.sh の raw 取得関数が現状の sed/awk 抽出と同一テキストを返すため寄せる。
        let load = metric("load")
        s.loadAvg = parser.parseLoadAvg(load)

        let swap = metric("swap")
        s.swapUsed = parser.parseSwapUsed(swap)

        let memFree = metric("free")
        s.memoryFreePct = parser.parseMemoryFreePct(memFree)

        // 02 §8.3 残置: boot epoch は MetricsParser に「生の boot 文字列」を渡す必要があり、
        // metrics.sh の uptime_days/hours は値を算出済みで返すため寄せると入力書式が変わる。固定文字列で残置。
        let bootStr = shellFixed("sysctl -n kern.boottime | awk '{print $4}' | tr -d ','")
        let now = Int(Date().timeIntervalSince1970)
        let uptime = parser.uptimeDaysHours(bootString: bootStr, nowEpoch: now)
        s.uptimeDays = uptime.days
        s.uptimeHours = uptime.hours

        // 02 §8.3 残置: MetricsParser.compressedGB は「生ページ数」を要求するが metrics.sh は GB へ
        // 換算済みを返すため寄せると入力書式が変わる。固定文字列で残置。
        let compPagesStr = shellFixed("vm_stat | awk '/Pages occupied by compressor/ {gsub(\"\\\\.\",\"\"); print $5}'")
        s.compressedGB = parser.compressedGB(pages: compPagesStr)

        let dockerRunning = shellFixed("pgrep -f 'com\\.apple\\.Virtualization\\.VirtualMachine' >/dev/null && echo 1 || echo 0")
            .trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        if dockerRunning {
            // 02 §8.3 残置: 3 秒タイムアウト（& wait）は単純な引数配列では再現困難。固定文字列で残置（注入なし）。
            let count = shellFixed("(docker ps -q 2>/dev/null | wc -l | tr -d ' ') & p=$!; (sleep 3; kill -9 $p 2>/dev/null) >/dev/null 2>&1 & wait $p 2>/dev/null")
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
