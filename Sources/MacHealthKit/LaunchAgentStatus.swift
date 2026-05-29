// Mac Health Keeper - LaunchAgentStatus（Domain・純粋値型 + パース関数）
//
// issue: 20260529_122242_LaunchAgentロード失敗調査と修正
//
// `launchctl print gui/<uid>/<label>` の出力をパースし、当該 LaunchAgent の load 状態を
// 表す pure 値型 `LaunchAgentStatus` に変換する Functional Core。MetricsCollectorPolicy /
// MetricsParser と同じ設計原則（実コマンド・FileManager・stderr 等の Infra に依存しない）。
//
// 既存 `install.sh` の verification は `launchctl list | grep <label>` を使っていたが、
// RunAtLoad=false + StartInterval-only な docker plist で launchd の internal list に
// 反映されるタイミングに依存して偽陽性（実際は load 成功なのに "ロード失敗" と判定）を
// 出す問題が memo/20260529_204726_root-cause-investigation.md §2-§3 で確定した。
// 本型は `launchctl print` 出力テキストから状態を判定する pure ロジックを提供する。

import Foundation

/// LaunchAgent 1 件の load 状態を表す純粋値。
///
/// `LaunchAgentStatus.parse(label:printOutput:)` で `launchctl print gui/<uid>/<label>` の
/// 標準出力テキストから決定的に生成される。`isLoaded` は notRunning / running の両方で true
/// を返す（launchd の用語では「state=not running」は次回スケジュール待ちで loaded 扱い）。
public struct LaunchAgentStatus: Equatable {

    /// LaunchAgent の状態区分。
    public enum Status: String, Equatable {
        /// `launchctl print` が "Could not find service" を返した（domain に bootstrap されていない）。
        case notFound
        /// `state = running`（現在実行中）。
        case running
        /// `state = not running`（loaded 済み、次回スケジュール待ち）。
        case notRunning
        /// 上記いずれにも一致しない出力（パース失敗・空文字・予期せぬ書式）。
        case unknown
    }

    /// 対象 LaunchAgent のラベル（例: `com.github.adachi-tatsuru.machealth.docker`）。
    public let label: String
    /// 判定結果。
    public let status: Status
    /// 判定に用いた `launchctl print` 出力の冒頭抜粋（最大 200 文字、UI/ログ表示用）。
    public let printOutputExcerpt: String

    public init(label: String, status: Status, printOutputExcerpt: String) {
        self.label = label
        self.status = status
        self.printOutputExcerpt = printOutputExcerpt
    }

    /// `bootstrap` 済みかどうか。`notRunning` も loaded 扱い。
    public var isLoaded: Bool {
        switch status {
        case .running, .notRunning: return true
        case .notFound, .unknown:   return false
        }
    }

    // MARK: - パース

    /// `launchctl print gui/<uid>/<label>` の標準出力テキストから状態を決定する。
    ///
    /// 判定優先順位:
    /// 1. "Could not find service" を含む → `.notFound`
    /// 2. "state = running"          を含む → `.running`
    /// 3. "state = not running"      を含む → `.notRunning`
    /// 4. 上記いずれにも当てはまらない → `.unknown`
    ///
    /// - parameter label: 対象 label（呼び出し元から渡す。出力テキスト内に label が無くてもよい）。
    /// - parameter printOutput: `launchctl print` の stdout テキスト（exit が非 0 の場合の stderr を含んでも可）。
    /// - returns: 決定的に生成された `LaunchAgentStatus`。
    public static func parse(label: String, printOutput: String) -> LaunchAgentStatus {
        let excerpt = excerptForDisplay(printOutput)

        // 1. notFound: launchctl print が typical な "Could not find service \"…\" in domain …" を返す
        if printOutput.contains("Could not find service") {
            return LaunchAgentStatus(label: label, status: .notFound, printOutputExcerpt: excerpt)
        }

        // 2. running: "state = running"（タブ・スペース揺れに耐える: 行から空白を除いて部分一致）
        let normalized = printOutput.replacingOccurrences(of: "\t", with: "")
                                    .replacingOccurrences(of: " ", with: "")
        if normalized.contains("state=running") {
            return LaunchAgentStatus(label: label, status: .running, printOutputExcerpt: excerpt)
        }
        // 3. notRunning: "state = not running"
        if normalized.contains("state=notrunning") {
            return LaunchAgentStatus(label: label, status: .notRunning, printOutputExcerpt: excerpt)
        }

        // 4. unknown: 何も判定材料がない（空文字含む）
        return LaunchAgentStatus(label: label, status: .unknown, printOutputExcerpt: excerpt)
    }

    /// 表示用に出力テキストを最大 200 文字に切り詰める（先頭優先）。
    /// 改行は半角スペースに正規化し、UI/ログ 1 行に乗せやすくする。
    private static func excerptForDisplay(_ text: String) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
                          .replacingOccurrences(of: "\r", with: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 200 { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 200)
        return String(trimmed[..<endIndex])
    }
}

/// 複数 LaunchAgent の状態を集計するための pure ヘルパ。
public enum LaunchAgentStatusSummary {

    /// `[LaunchAgentStatus]` から「N/M loaded」形式のサマリ文字列を作る。
    /// - parameter statuses: 対象 LaunchAgent 状態配列。
    /// - returns: 例 "4/4 loaded" / "3/4 loaded (NG: docker)" のような決定的文字列。
    public static func summaryLine(_ statuses: [LaunchAgentStatus]) -> String {
        let total = statuses.count
        let loadedCount = statuses.filter { $0.isLoaded }.count
        if loadedCount == total {
            return "\(loadedCount)/\(total) loaded"
        }
        let ngLabels = statuses.filter { !$0.isLoaded }.map { shortName(from: $0.label) }
        let joined = ngLabels.joined(separator: ", ")
        return "\(loadedCount)/\(total) loaded (NG: \(joined))"
    }

    /// 全件 loaded なら true。1 件でも notFound/unknown があれば false。
    public static func allLoaded(_ statuses: [LaunchAgentStatus]) -> Bool {
        guard !statuses.isEmpty else { return false }
        return statuses.allSatisfy { $0.isLoaded }
    }

    /// 失敗件数（isLoaded=false）。
    public static func failedCount(_ statuses: [LaunchAgentStatus]) -> Int {
        return statuses.filter { !$0.isLoaded }.count
    }

    /// label の末尾セグメント（"…machealth.monitor" → "monitor"）。
    static func shortName(from label: String) -> String {
        if let lastDot = label.lastIndex(of: ".") {
            return String(label[label.index(after: lastDot)...])
        }
        return label
    }
}
