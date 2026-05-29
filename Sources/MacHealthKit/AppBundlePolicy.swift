// Mac Health Keeper - .app バンドルの Info.plist 必須キー定義 / 検証 pure 関数群
//
// issue: 20260529_122727_Makefile_app化拡張（D331DD8F-C57D-4869-B6FF-B46CAB8E6F60）
//
// 目的:
//   `scripts/lib/build_app_bundle.sh` が組み立てる `.app` バンドルの Info.plist が
//   満たすべき必須キーの集合と、ビルド時に stamp されるキー（CFBundleVersion）を
//   pure-core の単一の真実として宣言する。シェル側のテスト・Swift 側のテストの
//   双方から本ポリシーを参照することで「必須キー一覧の二重宣言」を防ぐ。
//
// 設計判断:
//   - 値（CFBundleIdentifier の中身など）には踏み込まず、キーの存在のみを扱う。
//     ID や short version は別 issue / 別レイヤーの責務。
//   - Set<String> による pure 関数のみ（I/O なし）。
//   - CFBundleVersion は CI / install.sh / make build いずれの経路でも
//     `scripts/lib/version_stamp.sh` で stamp される単一キー。

import Foundation

/// `.app` バンドルの Info.plist に対するポリシー。
///
/// `scripts/lib/build_app_bundle.sh` がコピーする Info.plist と、`./install.sh` の
/// `src/Info.plist` 双方が満たすべき最低限の Info.plist キー集合を宣言する。
public enum AppBundlePolicy {

    /// `.app` バンドルが LSUIElement なメニューバーアプリとして
    /// 起動するために最低限必要な Info.plist キー集合。
    ///
    /// 各キーの値が「正しい値か」までは検証しない（その責務は別レイヤー）。
    public static let requiredInfoPlistKeys: Set<String> = [
        "CFBundleExecutable",
        "CFBundleIdentifier",
        "CFBundleName",
        "CFBundlePackageType",
        "CFBundleVersion",
        "CFBundleShortVersionString",
    ]

    /// ビルド時に `version_stamp.sh` が `git describe --tags --always` の出力で
    /// 上書きする Info.plist のキー名。
    ///
    /// `CFBundleShortVersionString`（ユーザー向け semver）は手動 bump を維持する。
    public static let stampedKey: String = "CFBundleVersion"

    /// 与えられたキー集合が必須キー集合を全て含むかどうか。
    ///
    /// - Parameter keys: Info.plist 由来のトップレベルキー集合
    /// - Returns: 必須キーが 1 件でも欠落していれば false
    public static func isValid(keys: Set<String>) -> Bool {
        return requiredInfoPlistKeys.isSubset(of: keys)
    }

    /// 与えられたキー集合のうち、必須キーから欠落しているもの。
    ///
    /// - Parameter keys: Info.plist 由来のトップレベルキー集合
    /// - Returns: 欠落キーの集合（無ければ空）
    public static func missingKeys(keys: Set<String>) -> Set<String> {
        return requiredInfoPlistKeys.subtracting(keys)
    }

    /// `stampedKey` が必須キー集合に含まれているか（自己整合性チェック用）。
    ///
    /// `requiredInfoPlistKeys` / `stampedKey` のどちらかを編集した際に
    /// pure-core BDD でズレを検知するためのプロパティ。
    public static var stampedKeyIsRequired: Bool {
        return requiredInfoPlistKeys.contains(stampedKey)
    }
}
