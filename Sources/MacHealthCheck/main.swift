// Mac Health Keeper - MacHealthCheck エントリポイント（XCTest 非依存テスト）
//
// issue: 20260529_083530_メトリクス非表示修正 フォロー
//
// XCTest が使えない環境（Command Line Tools のみ等）でも `swift run MacHealthCheck` で
// Functional Core の純粋関数群の BDD 単体テストを実行できるようにする。
// Tests/MacHealthKitTests/*.swift と同じ観点をカバーする一次経路（XCTest が使える環境では
// XCTest が追加で実行されるが、本実行ファイルは常に走る前提）。
//
// 形式は .agents/TEST_BDD_FORMAT.md に従い、useCase → scenario → Given/When/Then の入れ子
// で記述する。各 scenario の `When` ブロックでは被テスト対象を 1 回呼び、`Then` で assert する。
// 観点は 01_要件定義.md UC4 / UC5 / UC6（メトリクス収集の正常系・異常系・復旧系）に対応する。

import Foundation
import MacHealthKit

// MARK: - UC: MetricsCollectorPolicy（不在検知 → 伝播）

useCase("MetricsCollectorPolicy が metrics.sh の存在状態を MetricsSnapshot.collectorErrors と stderr 出力指示に正しく変換する") {

    scenario("metrics.sh が配置済み（exists=true）の場合、collectorErrors は空・stderr 出力なし・warned フラグはリセットされる") {
        // Given: metrics.sh が存在し、これまで未警告
        let exists = true
        let path = "/tmp/dummy/metrics.sh"
        let previouslyWarned = false

        // When: decide を呼ぶ
        let d = MetricsCollectorPolicy.decide(exists: exists, path: path, previouslyWarned: previouslyWarned)

        // Then: エラー追加なし・stderr 行なし・フラグは false（リセット）
        assertEqual(d.collectorErrorsToAppend, [], "存在時は collectorErrors に追加しない")
        assertEqual(d.stderrLineToWrite, nil, "存在時は stderr 出力指示なし")
        assertEqual(d.nextWarnedAboutMissingScript, false, "存在時は warned フラグをリセットする")
    }

    scenario("metrics.sh が不在（exists=false）かつ初回（previouslyWarned=false）の場合、collectorErrors 1 件追加・stderr 1 行出力・warned=true に遷移する") {
        // Given: metrics.sh が不在で、これまで警告未出力
        let exists = false
        let path = "/Users/test/.local/bin/mac-health/lib/metrics.sh"
        let previouslyWarned = false

        // When: decide を呼ぶ
        let d = MetricsCollectorPolicy.decide(exists: exists, path: path, previouslyWarned: previouslyWarned)

        // Then: collectorErrors にメッセージ 1 件、stderr 行は固定書式、フラグは true へ遷移
        assertEqual(d.collectorErrorsToAppend.count, 1, "不在初回は 1 件追加")
        assertEqual(d.collectorErrorsToAppend.first ?? "",
                    "metrics.sh not found: \(path) （./install.sh を再実行してください）",
                    "collectorErrors の文言が固定書式である")
        assertEqual(d.stderrLineToWrite ?? "",
                    "[MetricsCollector] metrics.sh not found: \(path)\n",
                    "stderr 行が固定書式・末尾改行付き")
        assertEqual(d.nextWarnedAboutMissingScript, true, "次回は警告済みとしてフラグを true にする")
    }

    scenario("metrics.sh が不在（exists=false）かつ警告済（previouslyWarned=true）の場合、collectorErrors 1 件追加は維持しつつ stderr 行は出さない（スパム抑止）") {
        // Given: metrics.sh が不在で、すでに stderr へ警告済み
        let exists = false
        let path = "/Users/test/.local/bin/mac-health/lib/metrics.sh"
        let previouslyWarned = true

        // When: decide を呼ぶ
        let d = MetricsCollectorPolicy.decide(exists: exists, path: path, previouslyWarned: previouslyWarned)

        // Then: collectorErrors は毎回追加するが、stderr 行は nil（1 度きり）
        assertEqual(d.collectorErrorsToAppend.count, 1, "不在中は毎収集サイクルで collectorErrors に積む（メニュー側がバナー継続）")
        assertEqual(d.stderrLineToWrite, nil, "不在 2 回目以降は stderr スパムを抑止する")
        assertEqual(d.nextWarnedAboutMissingScript, true, "警告済フラグは維持される")
    }

    scenario("不在 → 配置済みへ復旧した場合、warned フラグは false にリセットされ、次回再度不在になったときに stderr 警告を再び 1 度だけ出せる状態に戻る") {
        // Given: 直前まで不在で警告済（warned=true）、今回配置済みに復旧した
        let exists = true
        let path = "/tmp/metrics.sh"
        let previouslyWarned = true

        // When: decide を呼ぶ
        let d = MetricsCollectorPolicy.decide(exists: exists, path: path, previouslyWarned: previouslyWarned)

        // Then: 追加なし・stderr なし・フラグは false にリセット
        assertEqual(d.collectorErrorsToAppend, [], "復旧時は collectorErrors に追加しない")
        assertEqual(d.stderrLineToWrite, nil, "復旧時は stderr 出力なし")
        assertEqual(d.nextWarnedAboutMissingScript, false, "復旧時はフラグをリセットして次回不在時の警告を可能にする")
    }

    scenario("missingScriptCollectorError と missingScriptStderrLine はパス以外に補間値を含まない固定書式である") {
        // Given: 固定の絶対パス
        let path = "/abs/path/to/metrics.sh"

        // When: 公開ヘルパを直接呼ぶ
        let errorMsg = MetricsCollectorPolicy.missingScriptCollectorError(path: path)
        let stderrLine = MetricsCollectorPolicy.missingScriptStderrLine(path: path)

        // Then: 文言が固定で、パスのみが埋め込まれる
        assertEqual(errorMsg,
                    "metrics.sh not found: /abs/path/to/metrics.sh （./install.sh を再実行してください）",
                    "collectorError の固定書式が維持される")
        assertEqual(stderrLine,
                    "[MetricsCollector] metrics.sh not found: /abs/path/to/metrics.sh\n",
                    "stderr 行の固定書式が維持される（末尾改行込み）")
    }
}

// MARK: - UC: MenuModel が collectorErrors からエラーバナーを生成する

useCase("MenuModel が MetricsSnapshot.collectorErrors を受けてメニューにエラーバナーを挿入する") {

    let timing = ScheduleTiming()
    let catalog = JobCatalog()
    let cal = Calendar.utc
    let now = cal.date(2026, 5, 27, 12, 0)

    scenario("collectorErrors が空のとき、メニュー出力に警告ラベルは含まれない（既存メニューと等価）") {
        // Given: collectorErrors が空のスナップショット
        let snap = MetricsSnapshot()

        // When: MenuModel.build を呼ぶ
        let specs = MenuModel().build(snapshot: snap, catalog: catalog, timing: timing, now: now, calendar: cal)

        // Then: 「メトリクス取得不可」の文言を含む項目は存在しない
        let hasBanner = specs.contains { $0.title.contains("メトリクス取得不可") }
        assertFalse(hasBanner, "空 collectorErrors では警告バナーは挿入されない")
    }

    scenario("collectorErrors が 1 件以上あるとき、ヘッダー（index 0/1）直後の index 2/3 に警告ラベル + セパレータが挿入される") {
        // Given: collectorErrors を 1 件含むスナップショット
        var snap = MetricsSnapshot()
        snap.collectorErrors = ["metrics.sh not found: /path/to/missing"]

        // When: MenuModel.build を呼ぶ
        let specs = MenuModel().build(snapshot: snap, catalog: catalog, timing: timing, now: now, calendar: cal)

        // Then: ヘッダー → 警告ラベル → セパレータの順で挿入されている
        assertEqual(specs[0].title, "Mac Health Keeper", "index 0 はヘッダータイトル")
        assertEqual(specs[1].kind, .separator, "index 1 はヘッダー直後のセパレータ")
        assertEqual(specs[2].title, "⚠ メトリクス取得不可: ./install.sh を再実行してください", "index 2 は警告ラベル")
        assertEqual(specs[2].kind, .disabled, "index 2 は disabled 項目（クリック不可）")
        assertEqual(specs[3].kind, .separator, "index 3 はバナー直後のセパレータ")
        // And (Then): 既存のメトリクス行は後続で維持される
        let titles = specs.map { $0.title }
        assertTrue(titles.contains("  稼働時間:       0日 0時間"), "後続でメトリクス行が維持される")
    }

    scenario("errorBannerSpecs ヘルパは入力配列が空のとき空配列、1 件以上のとき 2 件（バナー + セパレータ）を返す") {
        // Given: MenuModel インスタンス
        let model = MenuModel()

        // When: 空配列で呼ぶ
        let empty = model.errorBannerSpecs([])
        // Then: 出力は空配列
        assertEqual(empty.count, 0, "空配列入力で空出力")

        // And (When): 1 件入力で呼ぶ
        let some = model.errorBannerSpecs(["something"])
        // And (Then): 出力はバナー + セパレータの 2 件
        assertEqual(some.count, 2, "非空入力で 2 件出力")
        assertEqual(some[0].title, "⚠ メトリクス取得不可: ./install.sh を再実行してください", "1 件目はバナー文言")
        assertEqual(some[1].kind, .separator, "2 件目はセパレータ")
    }
}

// MARK: - UC: MetricsParser フォールバック（特定指標のみ空文字を返した場合の挙動）

useCase("MetricsParser が空文字入力に対してフォールバック値 \"—\" を返し、他指標の取得には影響しない") {

    scenario("loadAvg のみ空文字、他指標は値ありのとき、loadAvg のみ \"—\" になり他指標は維持される") {
        // Given: load が空文字、swap と memFree は値あり
        let parser = MetricsParser()
        let loadText = ""
        let swapText = "512.00M"
        let memFreeText = "78"

        // When: 各指標をパースする
        let load = parser.parseLoadAvg(loadText)
        let swap = parser.parseSwapUsed(swapText)
        let mem = parser.parseMemoryFreePct(memFreeText)

        // Then: load のみ "—"、他は素の値が保持される
        assertEqual(load, "—", "空文字入力の load は \"—\" にフォールバック")
        assertEqual(swap, "512.00M", "値ありの swap は保持される")
        assertEqual(mem, "78", "値ありの memFree は保持される")
    }

    scenario("全指標が空文字（metrics.sh 完全不在の状況）でも parser はクラッシュせず全て \"—\" を返す") {
        // Given: 全て空文字
        let parser = MetricsParser()

        // When: 各指標をパースする
        let load = parser.parseLoadAvg("")
        let swap = parser.parseSwapUsed("")
        let mem = parser.parseMemoryFreePct("")

        // Then: 全て "—"（既存挙動）
        assertEqual(load, "—", "load フォールバック")
        assertEqual(swap, "—", "swap フォールバック")
        assertEqual(mem, "—", "memFree フォールバック")
    }
}

// MARK: - 集計と終了

CheckRunner.shared.finishAndExit()
