// Mac Health Keeper - メニューバーアプリ
// 再起動なしで再起動相当の状態を保つ自動メンテシステムの一元管理 UI
//
// ビルド: swiftc MacHealth.swift ../Sources/MacHealthKit/ScheduleTiming.swift -o MacHealth
//   （純粋ロジックの ScheduleTiming を併せてコンパイルする複数ファイルビルド。install.sh も同様）
//   ※ 旧 `swiftc MacHealth.swift` 単一ファイルビルドは、ScheduleTiming 参照のため不可。

import Cocoa

// 各ジョブの状態スナップショット
struct JobStatus {
    var loaded: Bool = false
    var lastRun: Date? = nil
    var nextRun: Date? = nil
}

// メトリクスのスナップショット（キャッシュ用）
struct MetricsSnapshot {
    var uptimeDays: Int = 0
    var uptimeHours: Int = 0
    var loadAvg: String = "—"
    var memoryFreePct: String = "—"
    var compressedGB: String = "—"
    var swapUsed: String = "—"
    var dockerLine: String = "—"
    var jobs: [String: JobStatus] = [:]
    var lastUpdated: Date = .distantPast
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var refreshTimer: Timer?
    let metricsQueue = DispatchQueue(label: "MacHealth.metrics", qos: .background)

    var cache = MetricsSnapshot()

    let homeDir = NSHomeDirectory()
    var binDir: String { "\(homeDir)/.local/bin/mac-health/bin" }
    var machealthCLI: String { "\(binDir)/mac-health" }
    var launchAgentDir: String { "\(homeDir)/Library/LaunchAgents" }
    var logDir: String { "\(homeDir)/Library/Logs/MacHealth" }

    let jobs = ["monitor", "docker", "uptime", "refresh"]

    // ジョブの短い名前
    let jobShortNames: [String: String] = [
        "monitor": "メモリ／負荷監視",
        "docker":  "Dockerアイドル監視",
        "uptime":  "長期稼働の通知",
        "refresh": "アプリ自動再起動"
    ]

    // 表示用の頻度
    let jobFrequencies: [String: String] = [
        "monitor": "5分毎",
        "docker":  "10分毎",
        "uptime":  "毎日 9:00",
        "refresh": "毎日 3:00"
    ]

    // ジョブごとの実行スケジュール種別（インターバル系 or カレンダー系）
    enum ScheduleKind { case interval(Int); case daily(Int, Int) }
    let jobSchedules: [String: ScheduleKind] = [
        "monitor": .interval(300),
        "docker":  .interval(600),
        "uptime":  .daily(9, 0),
        "refresh": .daily(3, 0)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusIcon()
        rebuildMenu()
        refreshMetricsAsync()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refreshMetricsAsync()
        }
    }

    func setStatusIcon() {
        guard let button = statusItem.button else { return }
        let candidates = ["stethoscope", "heart.text.square", "cross.case.fill", "waveform.path.ecg", "heart.fill"]
        for name in candidates {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Mac Health") {
                image.isTemplate = true
                if #available(macOS 11.0, *) {
                    let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
                    button.image = image.withSymbolConfiguration(config) ?? image
                } else {
                    button.image = image
                }
                button.imagePosition = .imageOnly
                return
            }
        }
        button.title = "🩺"
    }

    // MARK: - Metrics (Background)

    func refreshMetricsAsync() {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            let snapshot = self.gatherMetrics()
            DispatchQueue.main.async {
                self.cache = snapshot
                self.rebuildMenu()
            }
        }
    }

    func gatherMetrics() -> MetricsSnapshot {
        // 丸め・単位は scripts/lib/metrics.sh（02 §3.1.3）と一致させること。将来 (a) で metrics.sh へ統合。
        var s = MetricsSnapshot()

        let load = shell("uptime | sed -E 's/.*load averages?:?[[:space:]]+([0-9.]+).*/\\1/'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        s.loadAvg = load.isEmpty ? "—" : load

        let swap = shell("sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+M).*/\\1/'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        s.swapUsed = swap.isEmpty ? "—" : swap

        let memFree = shell("memory_pressure 2>/dev/null | awk -F': ' '/memory free percentage/ {gsub(\"%\",\"\",$2); print $2}'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        s.memoryFreePct = memFree.isEmpty ? "—" : memFree

        let bootStr = shell("sysctl -n kern.boottime | awk '{print $4}' | tr -d ','")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Int(Date().timeIntervalSince1970)
        let boot = Int(bootStr) ?? now
        let elapsed = now - boot
        s.uptimeDays = elapsed / 86400
        s.uptimeHours = (elapsed % 86400) / 3600

        let compPagesStr = shell("vm_stat | awk '/Pages occupied by compressor/ {gsub(\"\\\\.\",\"\"); print $5}'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compPages = Double(compPagesStr) ?? 0
        let compGB = compPages * 4096 / 1024 / 1024 / 1024
        s.compressedGB = String(format: "%.1f GB", compGB)

        let dockerRunning = shell("pgrep -f 'com\\.apple\\.Virtualization\\.VirtualMachine' >/dev/null && echo 1 || echo 0")
            .trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        if dockerRunning {
            let count = shell("(docker ps -q 2>/dev/null | wc -l | tr -d ' ') & p=$!; (sleep 3; kill -9 $p 2>/dev/null) >/dev/null 2>&1 & wait $p 2>/dev/null")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            s.dockerLine = "Docker:         起動中（コンテナ: \(count.isEmpty ? "?" : count)）"
        } else {
            s.dockerLine = "Docker:         停止中"
        }

        // 各ジョブの情報を収集
        for job in jobs {
            var status = JobStatus()
            let label = "com.github.adachi-tatsuru.machealth.\(job)"
            let out = shell("launchctl list 2>/dev/null | grep '\(label)'")
            status.loaded = !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // ログファイルの mtime を「最終実行」として使う
            let logPath = "\(logDir)/\(job).log"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
               let mtime = attrs[.modificationDate] as? Date {
                status.lastRun = mtime
            }

            // 次回実行時刻
            if let schedule = jobSchedules[job] {
                switch schedule {
                case .interval(let sec):
                    // インターバル系: 最終実行 + sec が次回（近似）
                    if let last = status.lastRun {
                        status.nextRun = last.addingTimeInterval(TimeInterval(sec))
                    }
                case .daily(let h, let m):
                    status.nextRun = nextDailyRun(hour: h, minute: m)
                }
            }

            s.jobs[job] = status
        }

        s.lastUpdated = Date()
        return s
    }

    // 純粋ロジックは ScheduleTiming に集約（テスト対象）。以下は内部委譲する薄いラッパ。
    private let timing = ScheduleTiming()

    func nextDailyRun(hour: Int, minute: Int) -> Date {
        return timing.nextDailyRun(hour: hour, minute: minute, now: Date(), calendar: Calendar.current)
    }

    // MARK: - Time formatting

    /// 「2分前」「3時間前」「2日前」など
    func relativeTimeShort(_ date: Date) -> String {
        return timing.relativeTimeShort(date, now: Date())
    }

    /// 「5分以内」「今日 09:00」「明日 03:00」「12/25 09:00」
    func relativeNext(_ date: Date, intervalSec: Int? = nil) -> String {
        return timing.relativeNext(date, intervalSec: intervalSec, now: Date(), calendar: Calendar.current)
    }

    // MARK: - Menu

    func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let title = NSMenuItem(title: "Mac Health Keeper", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        // 現状メトリクス
        let metricLines = [
            "稼働時間:       \(cache.uptimeDays)日 \(cache.uptimeHours)時間",
            "負荷平均(1分):  \(cache.loadAvg)",
            "空きメモリ:     \(cache.memoryFreePct)%",
            "圧縮メモリ:     \(cache.compressedGB)",
            "スワップ使用:   \(cache.swapUsed)",
            cache.dockerLine
        ]
        for line in metricLines {
            let item = NSMenuItem(title: "  " + line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if cache.lastUpdated != .distantPast {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss"
            let lu = NSMenuItem(title: "  最終更新: \(fmt.string(from: cache.lastUpdated))  (⌘R で更新)", action: #selector(refreshNow), keyEquivalent: "r")
            lu.target = self
            menu.addItem(lu)
        } else {
            let lu = NSMenuItem(title: "  取得中…", action: nil, keyEquivalent: "")
            lu.isEnabled = false
            menu.addItem(lu)
        }
        menu.addItem(.separator())

        // クイック対処
        let quickHeader = NSMenuItem(title: "クイック対処", action: nil, keyEquivalent: "")
        quickHeader.isEnabled = false
        menu.addItem(quickHeader)

        let quickRefreshApps = NSMenuItem(title: "🌀 重いアプリを今すぐリフレッシュ", action: #selector(quickAppRefresh), keyEquivalent: "")
        quickRefreshApps.target = self
        menu.addItem(quickRefreshApps)

        let quickPurge = NSMenuItem(title: "🧹 ファイルキャッシュ解放 (sudo purge)", action: #selector(quickPurge), keyEquivalent: "")
        quickPurge.target = self
        menu.addItem(quickPurge)

        let quickPressure = NSMenuItem(title: "📉 メモリ圧迫テスト (解放を促す)", action: #selector(quickMemoryPressure), keyEquivalent: "")
        quickPressure.target = self
        menu.addItem(quickPressure)

        let quickDockerQuit = NSMenuItem(title: "🐳 Docker Desktop を Quit", action: #selector(quickDockerQuit), keyEquivalent: "")
        quickDockerQuit.target = self
        menu.addItem(quickDockerQuit)
        menu.addItem(.separator())

        // ジョブ一覧（新表示）
        let jobsHeader = NSMenuItem(title: "ジョブ（クリックで ON/OFF を切替）", action: nil, keyEquivalent: "")
        jobsHeader.isEnabled = false
        menu.addItem(jobsHeader)

        for job in jobs {
            let status = cache.jobs[job] ?? JobStatus()
            let icon = status.loaded ? "🟢" : "⚪"
            let name = jobShortNames[job] ?? job
            let freq = jobFrequencies[job] ?? ""

            // 詳細部分: 「最終 X分前」or「次回 X」
            var extras: [String] = [freq]
            if let schedule = jobSchedules[job] {
                switch schedule {
                case .interval(let sec):
                    // インターバル系: 最終実行を表示
                    if let last = status.lastRun {
                        extras.append("最終 \(relativeTimeShort(last))")
                    } else if status.loaded {
                        extras.append("未実行")
                    }
                    // OFF だと次回も無いのでスキップ
                    _ = sec
                case .daily(_, _):
                    // カレンダー系: 次回実行を表示
                    if status.loaded, let next = status.nextRun {
                        extras.append("次回 \(relativeNext(next))")
                    }
                }
            }

            let extra = extras.joined(separator: " ・ ")
            let item = NSMenuItem(title: "\(icon)  \(name)    \(extra)", action: #selector(toggleJob(_:)), keyEquivalent: "")
            item.representedObject = job
            item.target = self
            // ツールチップに詳細
            var tipParts: [String] = ["ラベル: com.github.adachi-tatsuru.machealth.\(job)"]
            if let last = status.lastRun {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy/MM/dd HH:mm:ss"
                tipParts.append("最終実行: \(fmt.string(from: last))")
            }
            if status.loaded, let next = status.nextRun {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy/MM/dd HH:mm"
                tipParts.append("次回実行: \(fmt.string(from: next))")
            }
            item.toptip(tipParts.joined(separator: "\n"))
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // 即実行
        let runHeader = NSMenuItem(title: "今すぐ実行", action: nil, keyEquivalent: "")
        runHeader.isEnabled = false
        menu.addItem(runHeader)
        for job in jobs {
            let label = "  ▶ " + (jobShortNames[job] ?? job)
            let item = NSMenuItem(title: label, action: #selector(runJob(_:)), keyEquivalent: "")
            item.representedObject = job
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // ログ・通知テスト
        let openEvents = NSMenuItem(title: "通知履歴を開く", action: #selector(openEventsLog), keyEquivalent: "e")
        openEvents.target = self
        menu.addItem(openEvents)
        let openMonitor = NSMenuItem(title: "監視ログを開く", action: #selector(openMonitorLog), keyEquivalent: "m")
        openMonitor.target = self
        menu.addItem(openMonitor)
        let testNotif = NSMenuItem(title: "通知テスト", action: #selector(testNotification), keyEquivalent: "t")
        testNotif.target = self
        menu.addItem(testNotif)
        menu.addItem(.separator())

        let pauseAll = NSMenuItem(title: "全ジョブを停止", action: #selector(pauseAllJobs), keyEquivalent: "")
        pauseAll.target = self
        menu.addItem(pauseAll)
        let resumeAll = NSMenuItem(title: "全ジョブを再開", action: #selector(resumeAllJobs), keyEquivalent: "")
        resumeAll.target = self
        menu.addItem(resumeAll)
        menu.addItem(.separator())

        let helpItem = NSMenuItem(title: "📚 各指標の意味…", action: #selector(showMetricsHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        let about = NSMenuItem(title: "このアプリについて…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Mac Health を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Quick Actions

    @objc func refreshNow() {
        refreshMetricsAsync()
    }

    @objc func quickAppRefresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.shell("'\(self.machealthCLI)' run refresh")
            DispatchQueue.main.async {
                self.refreshMetricsAsync()
            }
        }
        notify("🌀 重いアプリのリフレッシュを開始しました")
    }

    @objc func quickPurge() {
        let alert = NSAlert()
        alert.messageText = "sudo purge を実行しますか？"
        alert.informativeText = "ファイルシステムキャッシュを解放します。\nターミナルが開いてパスワードを聞かれます。"
        alert.addButton(withTitle: "ターミナルで実行")
        alert.addButton(withTitle: "キャンセル")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = shell("""
                osascript -e 'tell application "Terminal" to activate' \
                          -e 'tell application "Terminal" to do script "sudo purge && echo \\"\\nDone. このウィンドウは閉じて構いません。\\""'
                """)
        }
    }

    @objc func quickMemoryPressure() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.shell("memory_pressure -l warn 2>/dev/null || true")
            DispatchQueue.main.async {
                self.refreshMetricsAsync()
            }
        }
        notify("📉 メモリ圧迫テストを実行しました")
    }

    @objc func quickDockerQuit() {
        _ = shell("osascript -e 'quit app \"Docker Desktop\"'")
        notify("🐳 Docker Desktop を Quit しました")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.refreshMetricsAsync()
        }
    }

    // MARK: - Job Control

    @objc func toggleJob(_ sender: NSMenuItem) {
        guard let job = sender.representedObject as? String else { return }
        let label = "com.github.adachi-tatsuru.machealth.\(job)"
        let plist = "\(launchAgentDir)/\(label).plist"
        let uid = String(getuid())
        let wasLoaded = cache.jobs[job]?.loaded ?? false

        // オプティミスティック更新
        if cache.jobs[job] == nil { cache.jobs[job] = JobStatus() }
        cache.jobs[job]?.loaded = !wasLoaded
        rebuildMenu()

        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            if wasLoaded {
                result = self.shell("launchctl bootout gui/\(uid)/\(label) 2>&1 || launchctl unload '\(plist)' 2>&1")
            } else {
                result = self.shell("launchctl bootstrap gui/\(uid) '\(plist)' 2>&1 || launchctl load '\(plist)' 2>&1")
            }

            Thread.sleep(forTimeInterval: 0.7)
            let actualLoaded = !self.shell("launchctl list 2>/dev/null | grep '\(label)'")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            DispatchQueue.main.async {
                self.cache.jobs[job]?.loaded = actualLoaded
                self.rebuildMenu()

                if actualLoaded == wasLoaded {
                    let action = wasLoaded ? "停止" : "起動"
                    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hint = trimmed.isEmpty ? "" : "\n\n\(trimmed)"
                    let alert = NSAlert()
                    alert.messageText = "ジョブの\(action)に失敗しました"
                    alert.informativeText = "「\(self.jobShortNames[job] ?? job)」の\(action)を試みましたが、状態が変わりませんでした。\(hint)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
        }
    }

    @objc func runJob(_ sender: NSMenuItem) {
        guard let job = sender.representedObject as? String else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.shell("'\(self.machealthCLI)' run \(job)")
            DispatchQueue.main.async {
                self.refreshMetricsAsync()
            }
        }
    }

    @objc func pauseAllJobs() {
        for job in jobs {
            if cache.jobs[job] == nil { cache.jobs[job] = JobStatus() }
            cache.jobs[job]?.loaded = false
        }
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.shell("'\(self.machealthCLI)' disable")
            Thread.sleep(forTimeInterval: 0.7)
            DispatchQueue.main.async {
                self.refreshMetricsAsync()
            }
        }
    }

    @objc func resumeAllJobs() {
        for job in jobs {
            if cache.jobs[job] == nil { cache.jobs[job] = JobStatus() }
            cache.jobs[job]?.loaded = true
        }
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.shell("'\(self.machealthCLI)' enable")
            Thread.sleep(forTimeInterval: 0.7)
            DispatchQueue.main.async {
                self.refreshMetricsAsync()
            }
        }
    }

    // MARK: - Logs

    @objc func openEventsLog() {
        let path = "\(logDir)/events.log"
        _ = shell("touch '\(path)' && open -a Console '\(path)'")
    }

    @objc func openMonitorLog() {
        let path = "\(logDir)/monitor.log"
        _ = shell("touch '\(path)' && open -a Console '\(path)'")
    }

    @objc func testNotification() {
        _ = shell("'\(machealthCLI)' test")
    }

    // MARK: - Help / About

    @objc func showMetricsHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "各指標の意味と見方"
        alert.informativeText = """
            重要度の高い順:

            ★★★ 空きメモリ %
              30% 以上なら健全。10% 未満は危険。
              体感速度に最も直結する指標。

            ★★★ メモリプレッシャー (通知に含まれる)
              normal / warn / critical の 3 段階。

            ★★  圧縮メモリ
              使われていないメモリを macOS が圧縮した量。
              増え続けるならメモリリーク疑い。10GB 超で警告。

            ★   負荷平均 (1分)
              ここ1分間の CPU 待ち行列の長さ。

            ★   スワップ使用
              今この瞬間スワップに書かれているメモリ量。
              ⚠ macOS は一度スワップに書いたページを
              積極的に戻さないので、過去の圧迫の名残が
              残り続けます。GB クラスでも空きメモリが
              高ければ実害は少ないことが多いです。

            ────────────────────────
            ジョブ表示の見方:
              🟢 = 動作中 / ⚪ = 停止中
              インターバル系: 「最終 X分前」 = 最後に動いた時刻
              カレンダー系:   「次回 X」 = 次に動く予定
              ※ クリックで ON/OFF を切替できます

            ────────────────────────
            スワップ使用が増えた時の改善（効果順）:
              1. 重いアプリを Quit & 再起動
                 → 「クイック対処 > 重いアプリを今すぐリフレッシュ」
              2. ファイルキャッシュ解放 (sudo purge)
              3. メモリ圧迫テストでアプリに解放を促す
              4. Mac 再起動（完全リセット）
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mac Health Keeper"
        alert.informativeText = """
            再起動なしで再起動相当の状態を保つ
            自動メンテナンスシステム

            • メモリ／負荷監視（5分毎）
            • Dockerアイドル監視（10分毎）
            • 長期稼働の通知（毎日 9:00）
            • アプリ自動再起動（毎日 3:00）

            バージョン 1.2
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Notification

    func notify(_ message: String) {
        _ = shell("osascript -e 'display notification \"\(message.replacingOccurrences(of: "\"", with: "\\\""))\" with title \"Mac Health\"'")
    }

    // MARK: - Shell

    @discardableResult
    func shell(_ cmd: String) -> String {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-l", "-c", cmd]
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

// NSMenuItem にツールチップヘルパ
extension NSMenuItem {
    func toptip(_ text: String) {
        self.toolTip = text
    }
}

// エントリポイント。
// ScheduleTiming.swift を併せてコンパイルするため複数ファイルビルドとなり、
// トップレベルコードが使えない。挙動を変えずに @main で同等の起動処理を行う。
@main
struct MacHealthMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
