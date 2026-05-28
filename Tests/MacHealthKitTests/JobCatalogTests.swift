// Mac Health Keeper - JobCatalog の単体テスト（T1）
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
// 03 §2.1.4 のテスト仕様に対応する。

import XCTest
@testable import MacHealthKit

/// ユースケース: ジョブの静的定義（並び順・ラベル規則）を不変に保つ。
final class JobCatalogTests: XCTestCase {

    /// シナリオ: jobs の並び順と label(for:) が現状の launchd ラベルと一致する。
    func test_jobs_orderAndLabel_matchCurrentBehavior() {
        // Given: JobCatalog を用意する
        let catalog = JobCatalog()

        // When: jobs 並びと monitor のラベルを取得する
        let order = catalog.jobs
        let label = catalog.label(for: "monitor")

        // Then: 並び順とラベル規則が現状どおり
        XCTAssertEqual(order, ["monitor", "docker", "uptime", "refresh"])
        XCTAssertEqual(label, "com.github.adachi-tatsuru.machealth.monitor")
    }

    /// シナリオ: 未知ジョブ ID の短名/頻度は nil で、表示側のフォールバック（?? job）に委ねる（境界）。
    func test_unknownJob_shortNameAndFrequency_areNil() {
        // Given: JobCatalog と未知のジョブ ID
        let catalog = JobCatalog()
        let unknown = "unknown_job"

        // When: shortNames/frequencies を引く
        let name = catalog.shortNames[unknown]
        let freq = catalog.frequencies[unknown]

        // Then: いずれも nil（呼び出し側が job ID にフォールバックする想定）
        XCTAssertNil(name)
        XCTAssertNil(freq)
    }
}
