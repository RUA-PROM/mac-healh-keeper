// Mac Health Keeper - MenuModel（UI・純粋データ生成）
//
// 現 src/MacHealth.swift rebuildMenu() L210-365 の「MetricsSnapshot/JobStatus/JobCatalog →
// メニュー項目データ」生成を純粋部に切り出したもの。NSMenu は作らず [MenuItemSpec] のみ生成する
// （AppKit 非依存・テスト対象）。項目・文言・順序・enabled・action・representedJob・tooltip・
// keyEquivalent を現状と完全一致させる（UC1-S1）。
//
// NSMenu への変換は src/MenuBuilder.swift（AppKit 部）が担う。

import Foundation

/// メニュー 1 項目のデータ構造（NSMenuItem を作らずデータだけ持つ）。
public struct MenuItemSpec: Equatable {
    public enum Kind: Equatable { case item, disabled, separator }
    public var kind: Kind
    public var title: String          // セパレータは ""
    public var isEnabled: Bool
    public var action: MenuAction?    // nil は非アクション項目
    public var keyEquivalent: String  // 例 "r","q",""（現状の keyEquivalent を保持）
    public var representedJob: String? // toggleJob/runJob 用のジョブ ID
    public var tooltip: String?       // ジョブ項目のツールチップ

    public init(kind: Kind,
                title: String,
                isEnabled: Bool,
                action: MenuAction? = nil,
                keyEquivalent: String = "",
                representedJob: String? = nil,
                tooltip: String? = nil) {
        self.kind = kind
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
        self.keyEquivalent = keyEquivalent
        self.representedJob = representedJob
        self.tooltip = tooltip
    }

    /// セパレータの spec。
    public static func separator() -> MenuItemSpec {
        MenuItemSpec(kind: .separator, title: "", isEnabled: false)
    }

    /// 非アクションの見出し/情報行（disabled）。
    public static func disabled(_ title: String) -> MenuItemSpec {
        MenuItemSpec(kind: .disabled, title: title, isEnabled: false)
    }
}

/// AppKit の #selector を純粋部に持ち込まないための action 識別子。
/// AppKit 部（MenuBuilder）が #selector にマッピングする。
public enum MenuAction: Equatable {
    case refreshNow, quickAppRefresh, quickPurge, quickMemoryPressure, quickDockerQuit
    case toggleJob, runJob
    case openEventsLog, openMonitorLog, testNotification
    case pauseAllJobs, resumeAllJobs, showMetricsHelp, showAbout, terminate
}

/// MetricsSnapshot から [MenuItemSpec] を生成する純粋部。
public struct MenuModel {

    public init() {}

    /// 同一入力に対し常に同一の配列を返す（決定的）。
    /// `now` を引数で受けるため相対時刻文言が固定でき、テストで安定する。
    /// `calendar` は現状の DateFormatter（既定 = ローカル）と整合させるため timezone の供給に使う。
    ///
    /// `snapshot.collectorErrors` が空でない場合、`headerSpecs` の直後に警告ラベル + セパレータを
    /// 1 件挿入する（issue: 20260529_083530_メトリクス非表示修正）。文言は固定で、ユーザーに
    /// metrics.sh 再配置の手段（./install.sh 再実行）を促す。
    public func build(snapshot: MetricsSnapshot,
                      catalog: JobCatalog,
                      timing: ScheduleTiming,
                      now: Date,
                      calendar: Calendar = .current) -> [MenuItemSpec] {
        var specs: [MenuItemSpec] = []
        specs += headerSpecs()
        specs += errorBannerSpecs(snapshot.collectorErrors)
        specs += metricsSpecs(snapshot: snapshot, calendar: calendar)
        specs += quickActionSpecs()
        specs += jobListSpecs(snapshot: snapshot, catalog: catalog, timing: timing, now: now, calendar: calendar)
        specs += runJobSpecs(catalog: catalog)
        specs += logSpecs()
        specs += bulkSpecs()
        specs += footerSpecs()
        return specs
    }

    /// 収集エラーがあれば警告ラベル + セパレータを返す。空なら `[]`（既存メニュー出力と等価）。
    /// 文言は固定リテラルで補間値を含まない。詳細（パス等）は stderr 側で出力する。
    ///
    /// `public` は XCTest 非搭載環境向け executable testrunner（MacHealthCheck）からの直接呼び出し
    /// のため必要（issue: 20260529_083530_メトリクス非表示修正 フォロー）。
    public func errorBannerSpecs(_ errors: [String]) -> [MenuItemSpec] {
        guard !errors.isEmpty else { return [] }
        return [
            .disabled("⚠ メトリクス取得不可: ./install.sh を再実行してください"),
            .separator(),
        ]
    }

    // MARK: - セクション（現 rebuildMenu の各ブロックと 1 対 1）

    /// タイトル＋セパレータ（現 L214-217）。
    func headerSpecs() -> [MenuItemSpec] {
        return [
            .disabled("Mac Health Keeper"),
            .separator(),
        ]
    }

    /// メトリクス 6 行＋最終更新/取得中行＋セパレータ（現 L219-244）。
    func metricsSpecs(snapshot s: MetricsSnapshot, calendar: Calendar) -> [MenuItemSpec] {
        var out: [MenuItemSpec] = []
        let metricLines = [
            "稼働時間:       \(s.uptimeDays)日 \(s.uptimeHours)時間",
            "負荷平均(1分):  \(s.loadAvg)",
            "空きメモリ:     \(s.memoryFreePct)%",
            "圧縮メモリ:     \(s.compressedGB)",
            "スワップ使用:   \(s.swapUsed)",
            s.dockerLine,
        ]
        for line in metricLines {
            out.append(.disabled("  " + line))
        }
        if s.lastUpdated != .distantPast {
            let fmt = DateFormatter()
            fmt.calendar = calendar
            fmt.timeZone = calendar.timeZone
            fmt.dateFormat = "HH:mm:ss"
            out.append(MenuItemSpec(kind: .item,
                                    title: "  最終更新: \(fmt.string(from: s.lastUpdated))  (⌘R で更新)",
                                    isEnabled: true,
                                    action: .refreshNow,
                                    keyEquivalent: "r"))
        } else {
            out.append(.disabled("  取得中…"))
        }
        out.append(.separator())
        return out
    }

    /// クイック対処 4 項目＋セパレータ（現 L246-266）。
    func quickActionSpecs() -> [MenuItemSpec] {
        return [
            .disabled("クイック対処"),
            MenuItemSpec(kind: .item, title: "🌀 重いアプリを今すぐリフレッシュ", isEnabled: true, action: .quickAppRefresh),
            MenuItemSpec(kind: .item, title: "🧹 ファイルキャッシュ解放 (sudo purge)", isEnabled: true, action: .quickPurge),
            MenuItemSpec(kind: .item, title: "📉 メモリ圧迫テスト (解放を促す)", isEnabled: true, action: .quickMemoryPressure),
            MenuItemSpec(kind: .item, title: "🐳 Docker Desktop を Quit", isEnabled: true, action: .quickDockerQuit),
            .separator(),
        ]
    }

    /// ジョブ一覧（icon・名前・extras・tooltip）＋セパレータ（現 L268-319）。
    func jobListSpecs(snapshot: MetricsSnapshot,
                      catalog: JobCatalog,
                      timing: ScheduleTiming,
                      now: Date,
                      calendar: Calendar) -> [MenuItemSpec] {
        var out: [MenuItemSpec] = []
        out.append(.disabled("ジョブ（クリックで ON/OFF を切替）"))

        for job in catalog.jobs {
            let status = snapshot.jobs[job] ?? JobStatus()
            let icon = status.loaded ? "🟢" : "⚪"
            let name = catalog.shortNames[job] ?? job
            let freq = catalog.frequencies[job] ?? ""

            // 詳細部分: 「最終 X分前」or「次回 X」（現 L280-298 と同一ロジック）
            var extras: [String] = [freq]
            if let schedule = catalog.schedules[job] {
                switch schedule {
                case .interval(let sec):
                    if let last = status.lastRun {
                        extras.append("最終 \(timing.relativeTimeShort(last, now: now))")
                    } else if status.loaded {
                        extras.append("未実行")
                    }
                    _ = sec
                case .daily(_, _):
                    if status.loaded, let next = status.nextRun {
                        extras.append("次回 \(timing.relativeNext(next, now: now, calendar: calendar))")
                    }
                }
            }

            let extra = extras.joined(separator: " ・ ")

            // ツールチップ（現 L304-316 と同一ロジック）
            var tipParts: [String] = ["ラベル: \(catalog.label(for: job))"]
            if let last = status.lastRun {
                let fmt = DateFormatter()
                fmt.calendar = calendar
                fmt.timeZone = calendar.timeZone
                fmt.dateFormat = "yyyy/MM/dd HH:mm:ss"
                tipParts.append("最終実行: \(fmt.string(from: last))")
            }
            if status.loaded, let next = status.nextRun {
                let fmt = DateFormatter()
                fmt.calendar = calendar
                fmt.timeZone = calendar.timeZone
                fmt.dateFormat = "yyyy/MM/dd HH:mm"
                tipParts.append("次回実行: \(fmt.string(from: next))")
            }

            out.append(MenuItemSpec(kind: .item,
                                    title: "\(icon)  \(name)    \(extra)",
                                    isEnabled: true,
                                    action: .toggleJob,
                                    representedJob: job,
                                    tooltip: tipParts.joined(separator: "\n")))
        }
        out.append(.separator())
        return out
    }

    /// 「今すぐ実行」＋セパレータ（現 L321-332）。
    func runJobSpecs(catalog: JobCatalog) -> [MenuItemSpec] {
        var out: [MenuItemSpec] = []
        out.append(.disabled("今すぐ実行"))
        for job in catalog.jobs {
            let label = "  ▶ " + (catalog.shortNames[job] ?? job)
            out.append(MenuItemSpec(kind: .item,
                                    title: label,
                                    isEnabled: true,
                                    action: .runJob,
                                    representedJob: job))
        }
        out.append(.separator())
        return out
    }

    /// 通知履歴/監視ログ/通知テスト＋セパレータ（現 L334-344）。
    func logSpecs() -> [MenuItemSpec] {
        return [
            MenuItemSpec(kind: .item, title: "通知履歴を開く", isEnabled: true, action: .openEventsLog, keyEquivalent: "e"),
            MenuItemSpec(kind: .item, title: "監視ログを開く", isEnabled: true, action: .openMonitorLog, keyEquivalent: "m"),
            MenuItemSpec(kind: .item, title: "通知テスト", isEnabled: true, action: .testNotification, keyEquivalent: "t"),
            .separator(),
        ]
    }

    /// 全停止/全再開＋セパレータ（現 L346-352）。
    func bulkSpecs() -> [MenuItemSpec] {
        return [
            MenuItemSpec(kind: .item, title: "全ジョブを停止", isEnabled: true, action: .pauseAllJobs),
            MenuItemSpec(kind: .item, title: "全ジョブを再開", isEnabled: true, action: .resumeAllJobs),
            .separator(),
        ]
    }

    /// ヘルプ・about・終了（現 L354-362）。
    func footerSpecs() -> [MenuItemSpec] {
        return [
            MenuItemSpec(kind: .item, title: "📚 各指標の意味…", isEnabled: true, action: .showMetricsHelp),
            MenuItemSpec(kind: .item, title: "このアプリについて…", isEnabled: true, action: .showAbout),
            MenuItemSpec(kind: .item, title: "Mac Health を終了", isEnabled: true, action: .terminate, keyEquivalent: "q"),
        ]
    }
}
