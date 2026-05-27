// Mac Health Keeper - メニューバーアプリ
// 再起動なしで再起動相当の状態を保つ自動メンテシステムの一元管理 UI
//
// ビルド: swiftc MacHealth.swift -o MacHealth

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    let homeDir = NSHomeDirectory()
    var binDir: String { "\(homeDir)/.local/bin/mac-health/bin" }
    var machealthCLI: String { "\(binDir)/mac-health" }
    var launchAgentDir: String { "\(homeDir)/Library/LaunchAgents" }

    let jobs = ["monitor", "docker", "uptime", "refresh"]
    let jobLabels: [String: String] = [
        "monitor": "メモリ／負荷監視     （5分毎）",
        "docker":  "Dockerアイドル監視  （10分毎）",
        "uptime":  "長期稼働の通知       （毎日 9:00）",
        "refresh": "アプリ自動再起動     （毎日 3:00）"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock に出さない、メニューバーのみ
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusIcon()
        rebuildMenu()

        // 60 秒ごとにメニューを再構築（メトリクスとジョブ状態を最新化）
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    /// SF Symbols のテンプレート画像をアイコンに設定。ダーク/ライトモード自動追従。
    func setStatusIcon() {
        guard let button = statusItem.button else { return }
        // 候補を順に試す（環境により無いシンボルがあるため）
        let candidates = ["stethoscope", "heart.text.square", "cross.case.fill", "waveform.path.ecg", "heart.fill"]
        for name in candidates {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Mac Health") {
                image.isTemplate = true   // ← これがダークモード自動対応の鍵
                // メニューバー向けの適切なサイズ設定
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
        // フォールバック（絵文字）
        button.title = "🩺"
    }

    // MARK: - Menu

    func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // タイトル
        let title = NSMenuItem(title: "Mac Health Keeper", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        // 現状メトリクス
        for line in getMetrics() {
            let item = NSMenuItem(title: "  " + line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // ジョブの ON/OFF
        let jobsHeader = NSMenuItem(title: "ジョブ（クリックで切替）", action: nil, keyEquivalent: "")
        jobsHeader.isEnabled = false
        menu.addItem(jobsHeader)
        for job in jobs {
            let enabled = isJobLoaded(job: job)
            let label = jobLabels[job] ?? job
            let item = NSMenuItem(title: label, action: #selector(toggleJob(_:)), keyEquivalent: "")
            item.state = enabled ? .on : .off
            item.representedObject = job
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // 即実行
        let runHeader = NSMenuItem(title: "今すぐ実行", action: nil, keyEquivalent: "")
        runHeader.isEnabled = false
        menu.addItem(runHeader)
        for job in jobs {
            let label = "  ▶ " + (jobLabels[job] ?? job)
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

        // Pause / Resume All
        let pauseAll = NSMenuItem(title: "全ジョブを停止", action: #selector(pauseAllJobs), keyEquivalent: "")
        pauseAll.target = self
        menu.addItem(pauseAll)
        let resumeAll = NSMenuItem(title: "全ジョブを再開", action: #selector(resumeAllJobs), keyEquivalent: "")
        resumeAll.target = self
        menu.addItem(resumeAll)
        menu.addItem(.separator())

        // About / Quit
        let about = NSMenuItem(title: "このアプリについて…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Mac Health を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Metrics

    func getMetrics() -> [String] {
        let load = shell("uptime | sed -E 's/.*load averages?:?[[:space:]]+([0-9.]+).*/\\1/'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let swap = shell("sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+M).*/\\1/'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let memFree = shell("memory_pressure 2>/dev/null | awk -F': ' '/memory free percentage/ {gsub(\"%\",\"\",$2); print $2}'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bootStr = shell("sysctl -n kern.boottime | awk '{print $4}' | tr -d ','")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let now = Int(Date().timeIntervalSince1970)
        let boot = Int(bootStr) ?? now
        let elapsed = now - boot
        let days = elapsed / 86400
        let hours = (elapsed % 86400) / 3600

        // 圧縮メモリ (GB)
        let compPagesStr = shell("vm_stat | awk '/Pages occupied by compressor/ {gsub(\"\\\\.\",\"\"); print $5}'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compPages = Double(compPagesStr) ?? 0
        let compGB = compPages * 4096 / 1024 / 1024 / 1024
        let compStr = String(format: "%.1f GB", compGB)

        // Docker
        let dockerRunning = shell("pgrep -f 'com\\.apple\\.Virtualization\\.VirtualMachine' >/dev/null && echo 1 || echo 0")
            .trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        var dockerLine = "Docker:         停止中"
        if dockerRunning {
            let count = shell("docker ps -q 2>/dev/null | wc -l | tr -d ' '")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            dockerLine = "Docker:         起動中（コンテナ: \(count.isEmpty ? "?" : count)）"
        }

        return [
            "稼働時間:       \(days)日 \(hours)時間",
            "負荷平均(1分):  \(load)",
            "空きメモリ:     \(memFree)%",
            "圧縮メモリ:     \(compStr)",
            "スワップ使用:   \(swap)",
            dockerLine
        ]
    }

    // MARK: - Job Control

    func isJobLoaded(job: String) -> Bool {
        let label = "com.github.adachi-tatsuru.machealth.\(job)"
        let out = shell("launchctl list 2>/dev/null | grep '\(label)'")
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc func toggleJob(_ sender: NSMenuItem) {
        guard let job = sender.representedObject as? String else { return }
        let label = "com.github.adachi-tatsuru.machealth.\(job)"
        let plist = "\(launchAgentDir)/\(label).plist"
        let uid = shell("id -u").trimmingCharacters(in: .whitespacesAndNewlines)
        if isJobLoaded(job: job) {
            _ = shell("launchctl bootout gui/\(uid)/\(label) 2>/dev/null; launchctl unload '\(plist)' 2>/dev/null")
        } else {
            _ = shell("launchctl bootstrap gui/\(uid) '\(plist)' 2>/dev/null || launchctl load '\(plist)' 2>/dev/null")
        }
        rebuildMenu()
    }

    @objc func runJob(_ sender: NSMenuItem) {
        guard let job = sender.representedObject as? String else { return }
        // 重いジョブはバックグラウンドで実行
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.shell("'\(self.machealthCLI)' run \(job)")
            DispatchQueue.main.async {
                self.rebuildMenu()
            }
        }
    }

    @objc func pauseAllJobs() {
        _ = shell("'\(machealthCLI)' disable")
        rebuildMenu()
    }

    @objc func resumeAllJobs() {
        _ = shell("'\(machealthCLI)' enable")
        rebuildMenu()
    }

    // MARK: - Logs

    @objc func openEventsLog() {
        let path = "\(homeDir)/Library/Logs/MacHealth/events.log"
        _ = shell("touch '\(path)' && open -a Console '\(path)'")
    }

    @objc func openMonitorLog() {
        let path = "\(homeDir)/Library/Logs/MacHealth/monitor.log"
        _ = shell("touch '\(path)' && open -a Console '\(path)'")
    }

    @objc func testNotification() {
        _ = shell("'\(machealthCLI)' test")
    }

    // MARK: - About

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mac Health Keeper"
        alert.informativeText = """
            再起動なしで再起動相当の状態を保つ
            自動メンテナンスシステム

            • メモリ／負荷監視（5分毎）
                異常な負荷を通知
            • Dockerアイドル監視（10分毎）
                コンテナ無しの Docker を業務時間外に自動 Quit
            • 長期稼働の通知（毎日 9:00）
                30日超で再起動を控えめに推奨
            • アプリ自動再起動（毎日 3:00）
                Slack/Chatwork/Chrome/Firefox/Claude を順次再起動

            バージョン 1.0
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
