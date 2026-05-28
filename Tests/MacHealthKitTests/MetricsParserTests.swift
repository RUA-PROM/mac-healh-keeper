// Mac Health Keeper - MetricsParser の単体テスト（T2）
// BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
// 03 §2.2.4 のテスト仕様に対応する。

import XCTest
@testable import MacHealthKit

/// ユースケース: シェル出力テキスト/数値からメトリクス値を現状と同じ丸め・フォールバックで算出する。
final class MetricsParserTests: XCTestCase {
    private let parser = MetricsParser()

    /// シナリオ: 圧縮メモリのページ数を GB 文字列に変換する（振る舞い不変）。
    func test_compressedGB_whenPages262144_returnsOnePointZeroGB() {
        // Given: 1GB 相当のページ数 262144（262144*4096/1024^3 = 1.0）
        let pages = "262144"

        // When: compressedGB を呼ぶ
        let text = parser.compressedGB(pages: pages)

        // Then: "1.0 GB" が返る
        XCTAssertEqual(text, "1.0 GB")
    }

    /// シナリオ: 圧縮メモリのページ数が空/非数値なら 0 として "0.0 GB" を返す（フォールバック）。
    func test_compressedGB_whenEmpty_returnsZeroGB() {
        // Given: 空文字（抽出失敗相当）
        let pages = ""

        // When: compressedGB を呼ぶ
        let text = parser.compressedGB(pages: pages)

        // Then: 0 として "0.0 GB"
        XCTAssertEqual(text, "0.0 GB")
    }

    /// シナリオ: 空入力では現状どおりのフォールバック値 "—" を返す。
    func test_parseLoadAvg_whenEmpty_returnsDash() {
        // Given: 空文字（抽出失敗相当）
        let text = ""

        // When: parseLoadAvg を呼ぶ
        let load = parser.parseLoadAvg(text)

        // Then: フォールバック "—" を返す
        XCTAssertEqual(load, "—")
    }

    /// シナリオ: 非空の load テキストは trim してそのまま返す。
    func test_parseLoadAvg_whenValue_returnsTrimmed() {
        // Given: 前後に空白のある値
        let text = "  1.23\n"

        // When: parseLoadAvg を呼ぶ
        let load = parser.parseLoadAvg(text)

        // Then: trim 後の "1.23"
        XCTAssertEqual(load, "1.23")
    }

    /// シナリオ: 稼働時間 epoch 差を 日/時間 に変換する（90000 秒 = 1日1時間）。
    func test_uptimeDaysHours_whenOneDayOneHour_returnsExpected() {
        // Given: now と 90000 秒前の boot epoch
        let now = 1_700_000_000
        let boot = now - 90000

        // When: uptimeDaysHours を呼ぶ
        let r = parser.uptimeDaysHours(bootEpoch: boot, nowEpoch: now)

        // Then: (1, 1)
        XCTAssertEqual(r.days, 1)
        XCTAssertEqual(r.hours, 1)
    }

    /// シナリオ: boot 文字列が非数値なら now を boot とみなし 0日0時間（現状フォールバック）。
    func test_uptimeDaysHours_whenBootStringInvalid_returnsZero() {
        // Given: 非数値の boot 文字列
        let now = 1_700_000_000

        // When: uptimeDaysHours(bootString:) を呼ぶ
        let r = parser.uptimeDaysHours(bootString: "n/a", nowEpoch: now)

        // Then: boot=now となり (0, 0)
        XCTAssertEqual(r.days, 0)
        XCTAssertEqual(r.hours, 0)
    }

    /// シナリオ: Docker 停止中の行を生成する。
    func test_dockerLine_whenStopped_returnsStoppedLine() {
        // Given: 起動していない・コンテナ数空
        // When: dockerLine を呼ぶ
        let line = parser.dockerLine(running: false, containerCount: "")

        // Then: 停止中の文言
        XCTAssertEqual(line, "Docker:         停止中")
    }

    /// シナリオ: Docker 起動中・コンテナ 3 の行を生成する。
    func test_dockerLine_whenRunningWithCount_returnsRunningLine() {
        // Given: 起動中・コンテナ数 "3"
        // When: dockerLine を呼ぶ
        let line = parser.dockerLine(running: true, containerCount: "3")

        // Then: 起動中の文言（コンテナ: 3）
        XCTAssertEqual(line, "Docker:         起動中（コンテナ: 3）")
    }

    /// シナリオ: Docker 起動中だがコンテナ数が空なら "?" にフォールバックする（境界）。
    func test_dockerLine_whenRunningEmptyCount_returnsQuestionMark() {
        // Given: 起動中・コンテナ数空
        // When: dockerLine を呼ぶ
        let line = parser.dockerLine(running: true, containerCount: "")

        // Then: コンテナ数は "?"
        XCTAssertEqual(line, "Docker:         起動中（コンテナ: ?）")
    }
}
