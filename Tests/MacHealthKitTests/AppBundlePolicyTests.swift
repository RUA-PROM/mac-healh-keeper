// Mac Health Keeper - AppBundlePolicy の単体テスト
//
// issue: 20260529_122727_Makefile_app化拡張（D331DD8F-C57D-4869-B6FF-B46CAB8E6F60）
//
// `Sources/MacHealthKit/AppBundlePolicy.swift` の純粋関数群を XCTest で検証する。
// 同等の観点を XCTest 非依存の `MacHealthCheck`（pure-core BDD）でもカバーしており、
// XCTest 利用可能な環境では本テストも実行され、二重に回帰検知される。
//
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。

import XCTest
@testable import MacHealthKit

/// ユースケース:
/// AppBundlePolicy が `.app` バンドルの Info.plist 必須キー集合・stamp 対象キー・
/// 検証ヘルパを宣言的に提供し、`scripts/lib/build_app_bundle.sh` と Swift 側の
/// 期待を「単一の真実」に揃える。
final class AppBundlePolicyTests: XCTestCase {

    /// シナリオ: stampedKey が requiredInfoPlistKeys に含まれる（自己整合）。
    func test_stampedKey_isContained_inRequiredKeys() {
        // Given: AppBundlePolicy の定数
        let stamped = AppBundlePolicy.stampedKey
        let required = AppBundlePolicy.requiredInfoPlistKeys

        // When: stamped が required に含まれるかを確認
        let contained = required.contains(stamped)

        // Then: 含まれる
        XCTAssertTrue(contained, "stampedKey '\(stamped)' は requiredInfoPlistKeys に含まれること")
        XCTAssertTrue(AppBundlePolicy.stampedKeyIsRequired,
                      "stampedKeyIsRequired プロパティが true")
    }

    /// シナリオ: requiredInfoPlistKeys は固定 6 キーを含む。
    func test_requiredInfoPlistKeys_containsExactly6FixedKeys() {
        // Given: requiredInfoPlistKeys
        let keys = AppBundlePolicy.requiredInfoPlistKeys

        // When: 個別キーをチェック
        // Then: 6 個含む
        XCTAssertEqual(keys.count, 6)
        XCTAssertTrue(keys.contains("CFBundleExecutable"))
        XCTAssertTrue(keys.contains("CFBundleIdentifier"))
        XCTAssertTrue(keys.contains("CFBundleName"))
        XCTAssertTrue(keys.contains("CFBundlePackageType"))
        XCTAssertTrue(keys.contains("CFBundleVersion"))
        XCTAssertTrue(keys.contains("CFBundleShortVersionString"))
    }

    /// シナリオ: 必須集合そのもので isValid=true、missing 空。
    func test_isValid_returnsTrue_forRequiredSet() {
        // Given: 必須集合そのもの
        let keys = AppBundlePolicy.requiredInfoPlistKeys

        // When: isValid / missingKeys を呼ぶ
        let valid = AppBundlePolicy.isValid(keys: keys)
        let missing = AppBundlePolicy.missingKeys(keys: keys)

        // Then: 検証成功
        XCTAssertTrue(valid)
        XCTAssertEqual(missing, [])
    }

    /// シナリオ: superset でも isValid=true。
    func test_isValid_returnsTrue_forSuperset() {
        // Given: 必須 + 追加 2 件
        var keys = AppBundlePolicy.requiredInfoPlistKeys
        keys.insert("LSUIElement")
        keys.insert("LSMinimumSystemVersion")

        // When: isValid / missingKeys を呼ぶ
        let valid = AppBundlePolicy.isValid(keys: keys)
        let missing = AppBundlePolicy.missingKeys(keys: keys)

        // Then: superset OK
        XCTAssertTrue(valid)
        XCTAssertEqual(missing, [])
    }

    /// シナリオ: CFBundleVersion 欠落で isValid=false、missing に CFBundleVersion。
    func test_isValid_returnsFalse_whenCFBundleVersionMissing() {
        // Given: CFBundleVersion を欠いた集合
        var keys = AppBundlePolicy.requiredInfoPlistKeys
        keys.remove("CFBundleVersion")

        // When: 検証
        let valid = AppBundlePolicy.isValid(keys: keys)
        let missing = AppBundlePolicy.missingKeys(keys: keys)

        // Then: 不正・欠落 1 件
        XCTAssertFalse(valid)
        XCTAssertEqual(missing, ["CFBundleVersion"])
    }

    /// シナリオ: 空集合で isValid=false、missing は必須集合と一致。
    func test_isValid_returnsFalse_forEmptySet() {
        // Given: 空集合
        let keys: Set<String> = []

        // When: 検証
        let valid = AppBundlePolicy.isValid(keys: keys)
        let missing = AppBundlePolicy.missingKeys(keys: keys)

        // Then: 不正・欠落は必須集合そのもの
        XCTAssertFalse(valid)
        XCTAssertEqual(missing, AppBundlePolicy.requiredInfoPlistKeys)
    }

    /// シナリオ: stampedKey は固定リテラル 'CFBundleVersion'。
    func test_stampedKey_isCFBundleVersion() {
        // Given: stampedKey
        // When: 値を取得
        let key = AppBundlePolicy.stampedKey

        // Then: 'CFBundleVersion' リテラルと一致
        XCTAssertEqual(key, "CFBundleVersion")
    }
}
