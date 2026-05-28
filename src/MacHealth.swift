// Mac Health Keeper - メニューバーアプリ
// 再起動なしで再起動相当の状態を保つ自動メンテシステムの一元管理 UI
//
// ビルド: 複数ファイル（src/*.swift ＋ Sources/MacHealthKit/*.swift）を swiftc でコンパイルする。
//   例: swiftc MacHealth.swift MetricsCollector.swift MenuBuilder.swift \
//         ../Sources/MacHealthKit/*.swift -o MacHealth
//   （Domain/Infra/UI の純粋部は Sources/MacHealthKit、AppKit/launchctl 依存部は src/。install.sh も同様。）
//   ※ 単一ファイルビルドは分割した型の参照のため不可。

// 注: swiftc ビルドでは src/*.swift と Sources/MacHealthKit/*.swift を 1 つのモジュールとして
// まとめてコンパイルするため import MacHealthKit は不要（型は同一モジュール内で解決される）。
import Cocoa

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

    // 各層の調整役として依存を保持する。
    private let runner: ShellRunner = ZshShellRunner()
    private let catalog = JobCatalog()
    private let timing = ScheduleTiming()
    private let menuModel = MenuModel()
    private let menuBuilder = MenuBuilder()
    private lazy var jobController = JobController(
        runner: runner,
        catalog: catalog,
        uid: String(getuid()),
        launchAgentDir: launchAgentDir,
        cliPath: machealthCLI
    )
    private lazy var collector = MetricsCollector(
        runner: runner,
        parser: MetricsParser(),
        catalog: catalog,
        jobController: jobController,
        timing: timing,
        logDir: logDir
    )

    /// 既存コマンド文字列をそのまま zsh -l -c で実行する（現 shell(_:) 互換）。
    @discardableResult
    private func shell(_ cmd: String) -> String {
        return runner.run("/bin/zsh", ["-l", "-c", cmd])
    }

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
            let snapshot = self.collector.collect()
            DispatchQueue.main.async {
                self.cache = snapshot
                self.rebuildMenu()
            }
        }
    }

    // MARK: - Menu

    func rebuildMenu() {
        let specs = menuModel.build(snapshot: cache, catalog: catalog, timing: timing, now: Date())
        let menu = menuBuilder.makeMenu(specs, target: self)
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
        let wasLoaded = cache.jobs[job]?.loaded ?? false

        // オプティミスティック更新
        if cache.jobs[job] == nil { cache.jobs[job] = JobStatus() }
        cache.jobs[job]?.loaded = !wasLoaded
        rebuildMenu()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.jobController.toggle(job: job, wasLoaded: wasLoaded)

            Thread.sleep(forTimeInterval: 0.7)
            let actualLoaded = self.jobController.isLoaded(job: job)

            DispatchQueue.main.async {
                self.cache.jobs[job]?.loaded = actualLoaded
                self.rebuildMenu()

                if actualLoaded == wasLoaded {
                    let action = wasLoaded ? "停止" : "起動"
                    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hint = trimmed.isEmpty ? "" : "\n\n\(trimmed)"
                    let alert = NSAlert()
                    alert.messageText = "ジョブの\(action)に失敗しました"
                    alert.informativeText = "「\(self.catalog.shortNames[job] ?? job)」の\(action)を試みましたが、状態が変わりませんでした。\(hint)"
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
        for job in catalog.jobs {
            if cache.jobs[job] == nil { cache.jobs[job] = JobStatus() }
            cache.jobs[job]?.loaded = false
        }
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.jobController.disableAll()
            Thread.sleep(forTimeInterval: 0.7)
            DispatchQueue.main.async {
                self.refreshMetricsAsync()
            }
        }
    }

    @objc func resumeAllJobs() {
        for job in catalog.jobs {
            if cache.jobs[job] == nil { cache.jobs[job] = JobStatus() }
            cache.jobs[job]?.loaded = true
        }
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.jobController.enableAll()
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
}

// エントリポイント。
// 複数ファイルビルドのためトップレベルコードが使えない。挙動を変えずに @main で同等の起動処理を行う。
@main
struct MacHealthMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
