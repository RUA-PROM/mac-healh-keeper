// Mac Health Keeper - About アラート末尾行のフォーマッタ（純粋関数）
//
// issue: 20260529_105524_ビルド時バージョン自動stamp
//
// 観点:
//   src/MacHealth.swift::showAbout の informativeText 末尾 1 行
//   「バージョン X.Y」のみを Bundle 動的取得に切り替える際の整形ロジックを、
//   テスト容易な pure function として MacHealthKit 側に切り出す。
//   入力は `Bundle.main.infoDictionary["CFBundleShortVersionString"] as? String` 経由。
//
// 仕様:
//   - 非 nil かつ非空文字列 -> "バージョン \(shortVersion!)" を返す。
//   - nil または空文字列 -> "バージョン 不明" を返す（fallback）。
//
// このファイルは AppKit に依存しない（Foundation のみ）。

import Foundation

/// About アラート末尾 1 行「バージョン X.Y」の文字列を返す純粋関数。
///
/// - Parameter shortVersion: `Bundle.main.infoDictionary["CFBundleShortVersionString"]` を
///   `as? String` で取り出した値。nil または空文字列の場合は "不明" にフォールバックする。
/// - Returns: "バージョン X.Y" または "バージョン 不明" の 1 行文字列。
public func formatAboutVersionLine(_ shortVersion: String?) -> String {
    guard let v = shortVersion, !v.isEmpty else {
        return "バージョン 不明"
    }
    return "バージョン \(v)"
}
