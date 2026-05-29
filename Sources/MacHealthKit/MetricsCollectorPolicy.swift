// Mac Health Keeper - MetricsCollectorPolicy（Domain・純粋関数）
//
// issue: 20260529_083530_メトリクス非表示修正 / フォローアップ（テスト可能化リファクタ）
//
// `MetricsCollector`（Imperative Shell）から「metrics.sh 不在検知 → MetricsSnapshot.collectorErrors
// への伝播・stderr 警告のスパム抑止フラグ管理」という Functional Core ロジックを切り出した純粋関数群。
// 実コマンド・FileManager・stderr 等の Infra には依存せず、入力は値で受ける（テスト対象）。
//
// 既存 `MetricsCollector` は本ファイルの関数を呼び出すだけになり、`FileManager.fileExists` の
// 真偽値と `warnedAboutMissingScript` 状態を入力として渡す。
//
// 設計原則: Functional Core / Imperative Shell（.agents/spec/01_設計原則.md）。
// 振る舞いは MetricsCollector 旧実装と完全一致させる（警告文言・配列追加・フラグ遷移）。

import Foundation

/// メトリクス収集経路の健全性チェックに関する純粋ロジック。
///
/// `metrics.sh` の存在チェック結果と、前回までに警告を出したかどうかのフラグ
/// （`warnedAboutMissingScript`）を入力に取り、以下を返す：
/// - `MetricsSnapshot.collectorErrors` に追加すべき文字列配列（空 or 1 件）
/// - stderr に書き込むべき 1 行（無しなら `nil`）
/// - 次回呼び出しに引き継ぐべき新しい `warnedAboutMissingScript` 値
///
/// 警告 stderr は不在の初回のみ 1 度きり出す。配置済みに戻ったらフラグをリセットして
/// 次回不在時に再度 1 度だけ警告できるようにする。
public enum MetricsCollectorPolicy {

    /// 警告メッセージ（メニュー警告ラベルではなく `collectorErrors` 配列に積む詳細メッセージ）。
    /// 文言は固定文字列とパスの連結のみ（補間値はパスのみ）。
    public static func missingScriptCollectorError(path: String) -> String {
        return "metrics.sh not found: \(path) （./install.sh を再実行してください）"
    }

    /// stderr に書き込む 1 行（末尾改行込み）。固定書式。
    public static func missingScriptStderrLine(path: String) -> String {
        return "[MetricsCollector] metrics.sh not found: \(path)\n"
    }

    /// 不在検知 1 サイクルの決定結果。
    public struct Decision: Equatable {
        /// `MetricsSnapshot.collectorErrors` に追加するメッセージ（空 or 1 件）。
        public let collectorErrorsToAppend: [String]
        /// stderr に書き出す行（無しなら `nil`）。
        public let stderrLineToWrite: String?
        /// 次回呼び出しに渡す `warnedAboutMissingScript` の新しい値。
        public let nextWarnedAboutMissingScript: Bool

        public init(collectorErrorsToAppend: [String],
                    stderrLineToWrite: String?,
                    nextWarnedAboutMissingScript: Bool) {
            self.collectorErrorsToAppend = collectorErrorsToAppend
            self.stderrLineToWrite = stderrLineToWrite
            self.nextWarnedAboutMissingScript = nextWarnedAboutMissingScript
        }
    }

    /// 不在検知の決定ロジック。
    /// - parameters:
    ///   - exists: `FileManager.fileExists(atPath: metricsShPath)` の結果。
    ///   - path: `metricsShPath`（警告メッセージ生成用）。
    ///   - previouslyWarned: 前回までに stderr に警告を出していれば `true`。
    /// - returns: 追加すべき collectorErrors、stderr に出す行、次回のフラグ値。
    public static func decide(exists: Bool,
                              path: String,
                              previouslyWarned: Bool) -> Decision {
        if exists {
            // 配置済み: エラー追加なし。警告フラグはリセット（次回不在時に再度 1 度だけ警告するため）。
            return Decision(collectorErrorsToAppend: [],
                            stderrLineToWrite: nil,
                            nextWarnedAboutMissingScript: false)
        }
        // 不在: collectorErrors に 1 件追加。stderr は初回のみ。
        let stderrLine: String? = previouslyWarned ? nil : missingScriptStderrLine(path: path)
        return Decision(
            collectorErrorsToAppend: [missingScriptCollectorError(path: path)],
            stderrLineToWrite: stderrLine,
            nextWarnedAboutMissingScript: true
        )
    }
}
