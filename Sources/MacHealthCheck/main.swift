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

// MARK: - UC: formatAboutVersionLine（About アラート末尾行のフォーマッタ）
//
// issue: 20260529_105524_ビルド時バージョン自動stamp
// 01_要件定義.md UC4 / UC5 に対応。
// Bundle.main.infoDictionary の動的取得は副作用付きで単体スタブ困難のため、
// 純粋関数 formatAboutVersionLine のみを対象とする（infoDictionary が nil を返す経路は手動確認）。

useCase("formatAboutVersionLine が CFBundleShortVersionString から About アラート末尾行を生成する") {

    scenario("非 nil・非空の semver が渡されたとき「バージョン X.Y」を返す") {
        // Given: semver 文字列 "1.3"
        let v: String? = "1.3"

        // When: formatAboutVersionLine を呼ぶ
        let line = formatAboutVersionLine(v)

        // Then: 「バージョン 1.3」を返す
        assertEqual(line, "バージョン 1.3", "正常系: semver がそのまま埋め込まれる")
    }

    scenario("nil が渡されたとき fallback「バージョン 不明」を返す") {
        // Given: Bundle.main.infoDictionary が CFBundleShortVersionString を持たない状況を模擬
        let v: String? = nil

        // When: formatAboutVersionLine を呼ぶ
        let line = formatAboutVersionLine(v)

        // Then: fallback 文言を返す
        assertEqual(line, "バージョン 不明", "nil 入力時は \"不明\" にフォールバック")
    }

    scenario("空文字列が渡されたとき fallback「バージョン 不明」を返す") {
        // Given: CFBundleShortVersionString が空文字（プロビジョニング異常等）
        let v: String? = ""

        // When: formatAboutVersionLine を呼ぶ
        let line = formatAboutVersionLine(v)

        // Then: fallback 文言を返す（空文字を素通ししない）
        assertEqual(line, "バージョン 不明", "空文字入力時は \"不明\" にフォールバック")
    }
}

// MARK: - UC: LaunchAgentStatus（launchctl print 出力のパース）
//
// issue: 20260529_122242_LaunchAgentロード失敗調査と修正
// 01_要件定義.md UC6-S1〜S3 + 境界の純粋関数アサーションを揃える。
// 既存 install.sh の `launchctl list | grep` 偽陽性問題（memo/20260529_204726_root-cause-investigation.md §2）
// を `launchctl print` ベース判定に置き換えるため、状態判定 pure 関数を強くカバーする。

useCase("LaunchAgentStatus.parse が launchctl print の出力テキストから状態を決定する") {

    scenario("出力に \"Could not find service\" を含む場合 status は notFound・isLoaded は false（01 UC6-S1）") {
        // Given: launchctl print のエラー出力テキスト（domain に bootstrap されていない場合の典型）
        let label = "com.github.adachi-tatsuru.machealth.docker"
        let printOutput = """
        Bad request.
        Could not find service "com.github.adachi-tatsuru.machealth.docker" in domain for user gui: 501
        """

        // When: parse を呼ぶ
        let s = LaunchAgentStatus.parse(label: label, printOutput: printOutput)

        // Then: notFound と判定され、isLoaded は false（bootstrap が必要）
        assertEqual(s.status, LaunchAgentStatus.Status.notFound, "Could not find service → notFound")
        assertFalse(s.isLoaded, "notFound は isLoaded=false")
        // And (Then): 出力抜粋が空でなく、判定材料が UI/ログに残る
        assertTrue(s.printOutputExcerpt.contains("Could not find service"),
                   "printOutputExcerpt にエラー文言を残す")
    }

    scenario("出力に \"state = running\" を含む場合 status は running・isLoaded は true（01 UC6-S2）") {
        // Given: launchctl print の通常出力で state = running が含まれる
        let label = "com.github.adachi-tatsuru.machealth.monitor"
        let printOutput = """
        gui/501/com.github.adachi-tatsuru.machealth.monitor = {
        \tactive count = 1
        \tpath = …
        \tstate = running
        }
        """

        // When: parse を呼ぶ
        let s = LaunchAgentStatus.parse(label: label, printOutput: printOutput)

        // Then: running と判定され、isLoaded は true
        assertEqual(s.status, LaunchAgentStatus.Status.running, "state = running → running")
        assertTrue(s.isLoaded, "running は isLoaded=true")
    }

    scenario("出力に \"state = not running\" を含む場合 status は notRunning・isLoaded は true（loaded 扱い・01 UC6-S3）") {
        // Given: launchctl print の通常出力で state = not running（次回スケジュール待ち）が含まれる
        let label = "com.github.adachi-tatsuru.machealth.uptime"
        let printOutput = """
        gui/501/com.github.adachi-tatsuru.machealth.uptime = {
        \tactive count = 0
        \tstate = not running
        \truns = 0
        }
        """

        // When: parse を呼ぶ
        let s = LaunchAgentStatus.parse(label: label, printOutput: printOutput)

        // Then: notRunning と判定され、isLoaded は true（bootstrap 済み・待機中）
        assertEqual(s.status, LaunchAgentStatus.Status.notRunning, "state = not running → notRunning")
        assertTrue(s.isLoaded, "notRunning も loaded 扱い（次回スケジュール待ち）")
    }

    scenario("空文字列入力に対しては status は unknown・isLoaded は false") {
        // Given: 空文字列（launchctl print が何も出さなかったコーナーケース）
        let label = "com.example.foo"
        let printOutput = ""

        // When: parse を呼ぶ
        let s = LaunchAgentStatus.parse(label: label, printOutput: printOutput)

        // Then: unknown 判定・isLoaded=false（誤って loaded 判定しない）
        assertEqual(s.status, LaunchAgentStatus.Status.unknown, "空文字は unknown")
        assertFalse(s.isLoaded, "unknown は isLoaded=false")
        // And (Then): 抜粋も空文字（情報の捏造をしない）
        assertEqual(s.printOutputExcerpt, "", "空入力に対しては抜粋も空")
    }

    scenario("notFound 判定は running/notRunning キーワードより優先される（同居する偽出力でも安全に notFound と扱う）") {
        // Given: ありえないが "Could not find service" と "state = running" が両方含まれる出力
        let label = "com.example.weird"
        let printOutput = "Could not find service \"x\" ... state = running"

        // When: parse を呼ぶ
        let s = LaunchAgentStatus.parse(label: label, printOutput: printOutput)

        // Then: notFound を優先（false positive を出さない安全方向の優先順）
        assertEqual(s.status, LaunchAgentStatus.Status.notFound, "notFound 優先")
        assertFalse(s.isLoaded, "notFound 優先 → isLoaded=false")
    }
}

// MARK: - UC: LaunchAgentStatusSummary（複数件サマリの pure ヘルパ）

useCase("LaunchAgentStatusSummary が複数 LaunchAgent 状態を集約して人間可読サマリを生成する") {

    scenario("全件 loaded（running 2 件 + notRunning 2 件）なら summaryLine は \"4/4 loaded\"") {
        // Given: 4 件すべて loaded（running/notRunning の混在）
        let arr = [
            LaunchAgentStatus(label: "com.example.a", status: .running,    printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.example.b", status: .notRunning, printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.example.c", status: .running,    printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.example.d", status: .notRunning, printOutputExcerpt: ""),
        ]

        // When: summaryLine を呼ぶ
        let line = LaunchAgentStatusSummary.summaryLine(arr)

        // Then: "4/4 loaded" を返す
        assertEqual(line, "4/4 loaded", "全件 loaded サマリ")
        // And (Then): allLoaded は true、failedCount は 0
        assertTrue(LaunchAgentStatusSummary.allLoaded(arr), "全件 loaded で allLoaded=true")
        assertEqual(LaunchAgentStatusSummary.failedCount(arr), 0, "失敗 0 件")
    }

    scenario("3/4 loaded で 1 件 notFound のとき NG ラベルが label の末尾セグメントで列挙される") {
        // Given: 1 件 notFound（docker）、3 件 loaded
        let arr = [
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.monitor", status: .notRunning, printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.docker",  status: .notFound,   printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.uptime",  status: .notRunning, printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.refresh", status: .running,    printOutputExcerpt: ""),
        ]

        // When: summaryLine を呼ぶ
        let line = LaunchAgentStatusSummary.summaryLine(arr)

        // Then: "3/4 loaded (NG: docker)" を返す（末尾セグメントのみ・順序維持）
        assertEqual(line, "3/4 loaded (NG: docker)", "1 件 NG のサマリは末尾セグメントを使う")
        // And (Then): allLoaded=false, failedCount=1
        assertFalse(LaunchAgentStatusSummary.allLoaded(arr), "1 件失敗なら allLoaded=false")
        assertEqual(LaunchAgentStatusSummary.failedCount(arr), 1, "失敗 1 件")
    }

    scenario("空配列に対しては allLoaded は false（true を返すと偽の安心感を与えるため）") {
        // Given: 空の状態配列
        let arr: [LaunchAgentStatus] = []

        // When: allLoaded を呼ぶ
        let all = LaunchAgentStatusSummary.allLoaded(arr)

        // Then: false（vacuous-true を避ける）
        assertFalse(all, "空配列で allLoaded=true にしない（偽の安心感を避ける）")
        // And (Then): failedCount は 0、summaryLine は "0/0 loaded"
        assertEqual(LaunchAgentStatusSummary.failedCount(arr), 0, "空配列の失敗件数は 0")
        assertEqual(LaunchAgentStatusSummary.summaryLine(arr), "0/0 loaded", "空配列のサマリは 0/0 loaded")
    }

    scenario("複数件 NG のときは NG ラベルが順序通り \", \" 区切りで列挙される") {
        // Given: 2 件 NG（docker, refresh）+ 2 件 loaded
        let arr = [
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.monitor", status: .running,    printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.docker",  status: .notFound,   printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.uptime",  status: .notRunning, printOutputExcerpt: ""),
            LaunchAgentStatus(label: "com.github.adachi-tatsuru.machealth.refresh", status: .unknown,    printOutputExcerpt: ""),
        ]

        // When: summaryLine を呼ぶ
        let line = LaunchAgentStatusSummary.summaryLine(arr)

        // Then: 順序維持で 2 件列挙される
        assertEqual(line, "2/4 loaded (NG: docker, refresh)", "NG 複数件は順序維持で列挙")
        assertEqual(LaunchAgentStatusSummary.failedCount(arr), 2, "失敗 2 件")
    }
}

// MARK: - UC: AppBundlePolicy（Info.plist 必須キーの宣言と検証）
//
// 関連 issue: 20260529_122727_Makefile_app化拡張（D331DD8F-C57D-4869-B6FF-B46CAB8E6F60）
// build_app_bundle.sh / install.sh / Makefile build のいずれの経路でも
// AppBundlePolicy.requiredInfoPlistKeys を満たすことが「壊れていない .app」の最低条件である。

useCase("AppBundlePolicy が Info.plist の必須キー集合・stamp 対象キー・検証ヘルパを pure に提供する") {

    scenario("requiredInfoPlistKeys と stampedKey の自己整合: stampedKey は必須キー集合に含まれる") {
        // Given: AppBundlePolicy の宣言済み定数
        let stamped = AppBundlePolicy.stampedKey
        let required = AppBundlePolicy.requiredInfoPlistKeys

        // When: stamped が required に含まれるかを問う
        let contained = required.contains(stamped)

        // Then: stampedKey は必ず requiredInfoPlistKeys のメンバである
        assertTrue(contained, "stampedKey '\(stamped)' は requiredInfoPlistKeys に含まれる")
        assertTrue(AppBundlePolicy.stampedKeyIsRequired,
                   "stampedKeyIsRequired プロパティが true（自己整合チェック）")
    }

    scenario("requiredInfoPlistKeys は 6 個の固定キーを含む（個別 key の存在チェック）") {
        // Given: requiredInfoPlistKeys
        let keys = AppBundlePolicy.requiredInfoPlistKeys

        // When: 個別 key を順に問う
        // Then: 6 個の必須キーが全て含まれる
        assertEqual(keys.count, 6, "必須キー数は 6")
        assertTrue(keys.contains("CFBundleExecutable"), "CFBundleExecutable 必須")
        assertTrue(keys.contains("CFBundleIdentifier"), "CFBundleIdentifier 必須")
        assertTrue(keys.contains("CFBundleName"), "CFBundleName 必須")
        assertTrue(keys.contains("CFBundlePackageType"), "CFBundlePackageType 必須")
        assertTrue(keys.contains("CFBundleVersion"), "CFBundleVersion 必須")
        assertTrue(keys.contains("CFBundleShortVersionString"), "CFBundleShortVersionString 必須")
    }

    scenario("必須キー集合と一致するキー集合は isValid=true、missingKeys は空") {
        // Given: requiredInfoPlistKeys そのもの
        let keys = AppBundlePolicy.requiredInfoPlistKeys

        // When: isValid と missingKeys を呼ぶ
        let valid = AppBundlePolicy.isValid(keys: keys)
        let missing = AppBundlePolicy.missingKeys(keys: keys)

        // Then: valid=true、missing は空
        assertTrue(valid, "必須キー一致集合は isValid=true")
        assertEqual(missing, [], "missingKeys は空")
    }

    scenario("必須キー集合に追加キーを足しても isValid は true のまま（superset を許容）") {
        // Given: 必須 + 追加 1 件（任意の Info.plist の現実）
        var keys = AppBundlePolicy.requiredInfoPlistKeys
        keys.insert("LSUIElement")
        keys.insert("LSMinimumSystemVersion")

        // When: isValid / missingKeys を呼ぶ
        let valid = AppBundlePolicy.isValid(keys: keys)
        let missing = AppBundlePolicy.missingKeys(keys: keys)

        // Then: valid=true（superset OK）、missing は空
        assertTrue(valid, "必須キーの superset は isValid=true")
        assertEqual(missing, [], "superset でも missingKeys は空")
    }

    scenario("CFBundleVersion を欠いた集合は isValid=false、missingKeys に CFBundleVersion が含まれる") {
        // Given: CFBundleVersion を削った集合
        var keys = AppBundlePolicy.requiredInfoPlistKeys
        keys.remove("CFBundleVersion")

        // When: isValid / missingKeys を呼ぶ
        let valid = AppBundlePolicy.isValid(keys: keys)
        let missing = AppBundlePolicy.missingKeys(keys: keys)

        // Then: valid=false、missing は CFBundleVersion を含む
        assertFalse(valid, "CFBundleVersion 欠落で isValid=false")
        assertTrue(missing.contains("CFBundleVersion"), "missingKeys に CFBundleVersion")
        assertEqual(missing.count, 1, "欠落は 1 件")
    }

    scenario("空集合は isValid=false、missingKeys は 6 件全て") {
        // Given: 空集合
        let keys: Set<String> = []

        // When: isValid / missingKeys を呼ぶ
        let valid = AppBundlePolicy.isValid(keys: keys)
        let missing = AppBundlePolicy.missingKeys(keys: keys)

        // Then: valid=false、missing は 6 件
        assertFalse(valid, "空集合は isValid=false")
        assertEqual(missing.count, 6, "missingKeys は必須キー数（6）と一致")
        assertEqual(missing, AppBundlePolicy.requiredInfoPlistKeys,
                    "空集合の missingKeys は requiredInfoPlistKeys そのもの")
    }

    scenario("stampedKey は固定値 'CFBundleVersion'") {
        // Given: AppBundlePolicy.stampedKey
        // When: 値を取り出す
        let key = AppBundlePolicy.stampedKey

        // Then: 'CFBundleVersion' リテラルと一致
        assertEqual(key, "CFBundleVersion", "stampedKey は 'CFBundleVersion'")
    }
}

// MARK: - 集計と終了

CheckRunner.shared.finishAndExit()
