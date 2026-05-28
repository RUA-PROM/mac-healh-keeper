---
document_id: "3693233B-2CF3-485F-BFA0-B4EDF906C464"
issue_id: "59F31A10-8DE7-41A5-8F94-32FA15C14A3B"
---

# レビュー書: サブ C メトリクス取得ロジックの重複解消

**プロジェクト名**: サブ C メトリクス取得ロジックの重複解消
**作成日**: 2026 年 05 月 28 日
**最終更新**: 2026 年 05 月 28 日

> **重要**: **このドキュメントは常に更新**。レビューで発見した問題点・改善提案・対応内容は即座に更新する。
>
> **用語**: [.agents/CONCEPTS.md §用語規約](../../../../.agents/CONCEPTS.md#用語規約) を参照。
> **必須**: 本レビューは [.agents/REVIEW_RULE.md](../../../../.agents/REVIEW_RULE.md) を参照して実施。レビュー深度は **full**（新規ファイル `metrics.sh` 追加＋2 箇所の参照置換＋テスト 2 本追加の中〜大規模変更）。

---

## 1. レビュー概要

### 1.1 レビュー目的（必須）

実装内容の確認・品質保証（メトリクス取得の DRY 集約が既存挙動・出力書式を破壊していないことの検証とクローズ判定）。

### 1.2 レビュー対象（必須）

- **実装範囲**: 生メトリクス取得を `scripts/lib/metrics.sh` に集約し、`scripts/bin/monitor.sh` と `scripts/bin/mac-health`（status）が source して参照。Swift は (b) 現状維持（ルール一致コメント 1 行のみ）。テスト `scripts/test/metrics.bats` / `metrics_test.sh` を追加し `make test-shell` に組込。README に開発・テスト節を追記。
- **レビュー期間**: 2026-05-28 ～ 2026-05-28
- **レビュー担当者**: 検証・レビュー worker（監査者）

---

## 2. 実装内容の確認

### 2.1 実装完了タスク（または Issue）

| タスク名 | 実装内容 | 実装日 | 担当者 | ステータス |
| -------- | -------- | ------ | ------ | ---------- |
| タスク1 metrics.sh 新設 | 純粋パース 7 関数＋取得ラッパ 9 関数を単一責務で新設（判定/通知/ログ非依存） | 2026-05-28 | 実装worker | 完了 |
| タスク2 monitor.sh 置換 | 取得部 4 箇所を `metrics_*` 呼び出しへ置換。判定/ログ/通知/`key:epoch` 不変 | 2026-05-28 | 実装worker | 完了 |
| タスク3 mac-health 置換 | [Current Metrics] 取得部を `metrics_*` へ置換。printf 書式・キー・単位完全不変 | 2026-05-28 | 実装worker | 完了 |
| タスク4 Swift (b) 対応 | `gatherMetrics()` 冒頭にルール一致コメント 1 行追加（挙動不変） | 2026-05-28 | 実装worker | 完了 |
| タスク5 テスト追加 | `metrics.bats`・`metrics_test.sh` 追加。Makefile フォールバックに追記 | 2026-05-28 | 実装worker | 完了 |
| タスク6 ドキュメント整合 | README 開発・テスト節追記、取得部コメント更新 | 2026-05-28 | 実装worker | 完了 |

### 2.2 実装内容の詳細

#### タスク 1: scripts/lib/metrics.sh

- **実装内容**: 純粋パース関数（`metrics_parse_swap_mb` / `metrics_parse_swap_raw` / `metrics_parse_compressed_gb` / `metrics_parse_load_1m` / `metrics_parse_load_1m_raw` / `metrics_parse_free_pct` / `metrics_uptime_days` / `metrics_uptime_hours`）と取得ラッパ（`metrics_swap_used_mb` / `metrics_swap_used_raw` / `metrics_compressed_gb` / `metrics_load_1m` / `metrics_load_1m_raw` / `metrics_memory_free_pct` / `metrics_uptime_days_now` / `metrics_uptime_hours_now` / `metrics_docker_status`）。
- **変更ファイル**: `scripts/lib/metrics.sh`（新規）。
- **実装方法**: Functional Core / Imperative Shell。純粋関数は引数でコマンド出力テキスト・ページ数・epoch を受け、外部コマンド非依存。ラッパは `2>/dev/null` で実コマンドを叩き純粋関数へ委譲。
- **確認事項**: `log.sh`/`notify.sh`/`thresholds.sh`/`notification_cooldown.sh` を source しない一方向依存であること（確認済・grep で 0 件）。

#### タスク 2/3: 参照側の置換（evidence: HEAD との diff）

- `monitor.sh`: 取得 4 行を `metrics_swap_used_mb`/`metrics_compressed_gb`/`metrics_load_1m`/`metrics_memory_free_pct` に置換。`log "$JOB" ...` のログ行・`notify`/`log_event`・`classify_pressure`/`exceeds_threshold`/`should_notify`・`ncpu`/`load_threshold`・`rotate_logs` は不変。
- `mac-health`: swap 表示は `metrics_swap_used_raw`（`512.00M` 形式維持）、load 表示は `metrics_load_1m_raw`（**未丸め `11.83` 形式維持**）、`metrics_compressed_gb`/`metrics_memory_free_pct`/`metrics_uptime_days_now`/`metrics_uptime_hours_now`/`metrics_docker_status` を使用。`printf` 各行は HEAD と byte 一致（diff 空）。

#### タスク 4: Swift gatherMetrics()

- `src/MacHealth.swift` L116 に `// 丸め・単位は scripts/lib/metrics.sh（02 §3.1.3）と一致させること。将来 (a) で metrics.sh へ統合。` を 1 行追加のみ。`gatherMetrics()` の抽出式・単位・丸めは現状維持（compressed=`%.1f`、swap=`used = ([0-9.]+M)` 抽出、load=未丸め抽出、uptime=整数除算）で metrics.sh と一致。

---

## 3. テスト結果の確認

### 3.1 単体テスト

#### テスト実行結果（必須: 数値で記載）

- **実行日**: 2026-05-28（JST）
- **実行コマンド**: `make test-shell`（bats 不在のため自前 assert ランナーへフォールバック）
- **テストファイル数**: 2（`scripts/test/monitor_test.sh`、`scripts/test/metrics_test.sh`。C の対象は metrics_test.sh）
- **テストケース数**: metrics_test.sh = 12、monitor_test.sh（A・回帰）= 9。合計 21
- **成功**: 21
- **失敗**: 0
- **スキップ**: 0

実行ログ抜粋（evidence_source: test_output）:

```
==> shell tests
    (bats not found -> fallback to self-made assert runner)
  ...（monitor_test.sh）shell tests: 9 passed, 0 failed
  ok   - UC1-S1: metrics_parse_swap_mb returns integer MB
  ok   - UC1-S2: metrics_parse_compressed_gb returns GB(1dp)
  ...
  ok   - UC2: load rounded keeps monitor current format
metrics shell tests: 12 passed, 0 failed
```

#### bats 不在時のフォールバック経路

- `bats` は本環境に **不在**。`Makefile` の `test-shell` は `command -v bats` 不成立時に `bash scripts/test/monitor_test.sh && bash scripts/test/metrics_test.sh` を実行する経路へフォールバックし、両者 PASS を確認した（evidence_source: test_output / existing_code = Makefile L19-25）。bats あり経路は `bats scripts/test/` のディレクトリ走査で `metrics.bats` を自動的に拾う設計（未検証だが bats 構文は monitor.bats と同形式で妥当）。

#### swift build / swift test

- `swift build` → `Build complete!`（exit 0）。Swift は (b) 現状維持でありビルドを破壊していないことを確認（evidence_source: test_output）。

#### 集約前後の出力一致（独立再検証・最重要）

監査者自身が `metrics.sh` を source し、各純粋関数の出力を**置換前の原抽出コマンド**（`sysctl vm.swapusage|sed`、`vm_stat|awk`、`uptime|sed`、`memory_pressure|awk`、`kern.boottime` 算術）と固定入力で照合した結果、**全項目 MATCH**（evidence_source: test_output）:

| 項目 | 固定入力 | 新（metrics.sh） | 原コマンド | 判定 |
| ---- | ---- | ---- | ---- | ---- |
| swap raw（`512.00M` 形式） | `...used = 512.00M...` | `512.00M` | `512.00M` | MATCH |
| swap MB | 同上 | `512` | `512` | MATCH |
| load raw（未丸め `11.83`） | `...load averages: 11.83 ...` | `11.83` | `11.83` | MATCH |
| load rounded（`%.1f`） | 同上 | `11.8` | `11.8` | MATCH |
| compressed GB | pages=3145728 | `12.0` | `12.0` | MATCH |
| memory free % | `...memory free percentage: 78%` | `78` | `78` | MATCH |
| uptime days | now/boot 固定 | `1` | `1` | MATCH |
| uptime hours | 同上 | `15` | `15` | MATCH |

さらに `mac-health` の printf 書式行・`monitor.sh` のログ行/通知文/log_event 行を HEAD と diff した結果、いずれも **byte 一致**（diff 空）。

#### 失敗したテスト

なし（0 件）。

### 3.2 統合テスト

- 参照一致（UC2-S1）は `metrics_test.sh` の「2 参照元で同値」「raw/MB 整合」ケースで単体近似的に検証（PASS）。実機 `mac-health status` / `monitor.log` の手動 diff は実機依存のため自動化対象外（03 §2.3.3 の方針どおり）。本監査では固定入力での原コマンド一致をもって書式不変を実証した。

### 3.3 E2E テスト

- 実コマンド実行ラッパ（実機依存）は 03 方針どおり自動 E2E 非対象。純粋関数テスト＋固定入力 diff で代替（A と同方針）。

---

## 4. コードレビュー

### 4.1 コード品質

#### コードスタイル

- **リント結果**: shellcheck 未実行（環境になし）。コード目視で `set -u` 配慮（`local` 既定値・`${1:-}`）あり、未定義変数を作らない。
- **フォーマット**: 問題なし（A の `notification_cooldown.sh` と同形式）。
- **型チェック**: `swift build` 緑（エラー 0）。

#### コードレビュー観点

| 観点 | 確認内容 | 結果 | コメント |
| ---- | ---- | ---- | ---- |
| 可読性 | 関数名が意図を表し、ヘッダコメントに原参照元・丸めルールを明記 | OK | 各関数に「monitor.sh Lxx と同一」等の対応が記載され追跡容易 |
| 保守性 | 取得を 1 箇所へ集約し、定義変更が単一修正で全参照に反映 | OK | 純粋/ラッパ分離でテスト容易・DRY 達成 |
| パフォーマンス | シェル 2 箇所は同一プロセス内 source。Swift (b) で追加プロセス起動ゼロ | OK | 01 §3.1 を満たす |
| セキュリティ | 固定コマンド・引数。ユーザー入力を直接展開しない | OK | 注入耐性の本格強化はサブ F の責務（範囲外） |

### 4.2 指摘事項

#### 指摘 1: 02 §5.1 API 一覧に純粋関数 `metrics_parse_swap_raw` が欠落

- **重要度**: 低
- **指摘内容**: 02 §5.1 の API 一覧表は純粋関数として `metrics_parse_swap_mb` を載せるが、実装・03・テストで使う `metrics_parse_swap_raw`（mac-health の `512.00M` 表示用パース）が表に未掲載。ラッパ `metrics_swap_used_raw` は記載あり。実装・テストは正しく `metrics_parse_swap_raw` を定義・使用しており**機能上の欠陥はない**（ドキュメント表の完全性のみ）。
- **対応状況**: 未対応（クローズ非阻害）
- **対応方法**: 02 §5.1 の純粋関数行に `metrics_parse_swap_raw`（swapusage テキスト → `512.00M` 文字列）を追記すると整合性が完全になる。本 issue でのコード修正は不要。

#### 指摘 2: monitor.sh の `:-0` フォールバック二重化（軽微・現状維持で可）

- **重要度**: 低
- **指摘内容**: `metrics_swap_used_mb`/`metrics_load_1m` は空入力時に内部で `0` を返すため、`monitor.sh` の `swap_used_mb=${swap_used_mb:-0}` / `load_1m=${load_1m:-0}` は冗長。ただし `set -u` 下の安全側保険として無害であり、挙動も不変。
- **対応状況**: 未対応（クローズ非阻害・現状維持で問題なし）
- **対応方法**: 任意。冗長除去するなら追って整理。

#### 改善（参考）: uptime の堅牢性向上

- mac-health の uptime は元々 `set -u` 下で `boot` が空だと `$(( (now - boot)/86400 ))` が算術エラーになり得たが、`metrics_uptime_days`/`hours` は boot 空時に now を代入し差 0 とする。**回帰ではなく堅牢性の改善**であり、通常運用（boot 取得可）では出力完全一致。指摘ではなく所見として記録。

---

## 5. ドキュメントの確認

### 5.1 ドキュメント更新状況

| ドキュメント | 更新状況 | 確認者 | 確認日 |
| ------------ | -------- | ------ | ------ |
| [`00_要求定義.md`](./00_要求定義.md) | 更新済み（document_id・issue_id 付与） | 監査者 | 2026-05-28 |
| [`01_要件定義.md`](./01_要件定義.md) | 更新済み（document_id 付与） | 監査者 | 2026-05-28 |
| [`02_設計.md`](./02_設計.md) | 更新済み（指摘1 の軽微な表追記が望ましい） | 監査者 | 2026-05-28 |
| [`03_実装計画.md`](./03_実装計画.md) | 更新済み（BDD↔テスト対応表あり） | 監査者 | 2026-05-28 |

### 5.2 ドキュメントの整合性

- **実装と設計の整合性**: 整合（02 §3.1.3 の丸め・単位・フォールバックと実装が一致。関数名は 03 §2.1.2 と一致）。
- **要件と実装の整合性**: 整合（01 UC1-S1/UC1-S2/UC2-S1 がテスト化済み）。
- **コメント**: 指摘1 の 02 §5.1 表のみ要追記（低）。

---

## 6. パフォーマンス確認

### 6.1 パフォーマンステスト結果

- シェル 2 箇所は同一プロセス内で `source` するため追加プロセス起動は増えない。Swift は (b) で追加プロセス起動ゼロ。01 §3.1（追加プロセス起動最小化）を満たす。

### 6.2 ボトルネックの確認

- なし。取得回数・コマンド呼び出し回数は集約前と同等。

---

## 7. セキュリティ確認

| 項目 | 確認内容 | 結果 | コメント |
| ---- | ---- | ---- | ---- |
| 認証・認可 | 該当なし（ローカル実行ユーティリティ） | OK | — |
| データ保護 | 固定コマンド・引数構成。ユーザー入力を直接展開しない | OK | 本格的な注入耐性強化はサブ F の責務（範囲外） |
| 入力検証 | 純粋関数は空/非数値入力でフォールバック（swap=0, compressed=0.0 等）を返す | OK | 異常系テストで検証済 |

---

## 8. デプロイ準備

### 8.1 デプロイチェックリスト

- [x] すべてのテストが通過している（shell 21/21、swift build 緑）
- [x] コードレビューが完了している
- [x] ドキュメントが更新されている（指摘1 の低優先の追記を除き整合）
- [ ] マイグレーションスクリプト（該当なし）
- [ ] 環境変数設定（該当なし）
- [ ] バックアップ計画（該当なし）

### 8.2 デプロイ計画

- 配布ビルドは install.sh の `swiftc`（SwiftPM 生成物は配布に含めない）。本 issue は挙動不変のため特別なロールバック不要。

---

## docs 更新

- 要否: **不要**
- 対象: なし
- 理由: 本変更は内部リファクタ（取得ロジックの集約）であり、出力書式・キー名・単位・閾値判定経路を変えず、システム仕様（docs/）に影響しないため。開発者向けの集約方針は README に追記済み。

---

## 9. 設計・境界の確認

### 9.1 設計の確認

- **設計原則の準拠**: UNIX 哲学・単一責務に準拠。`metrics.sh` は「取得」のみを担い、判定（A）・通知・ログを持たず source もしない一方向依存（grep で確認）。Functional Core / Imperative Shell（純粋/ラッパ分離）で A の構造と一貫（spec/01・06）。
- **ディレクトリ構成**: `scripts/lib/` 直下（`log.sh`/`notify.sh` と同層・深いネストなし）。spec/02 の shared 肥大化回避に適合（取得という単一目的に閉じる）。
- **命名規則**: spec/03 禁止命名（helpers/misc/common/utils）不使用。`metrics_*` で意図が分かる（grep で 0 件確認）。

### 9.2 境界・依存の確認

- **責務の境界**: 取得（metrics.sh）／判定（notification_cooldown.sh）／表示・通知（mac-health・monitor.sh）が分離。`metrics.sh` は閾値判定・通知・ログを含まない。
- **依存関係**: `mac-health`→`metrics.sh`、`monitor.sh`→`metrics.sh`（取得）＋`notification_cooldown.sh`（判定・C で不変）。循環参照なし。
- **Swift (b) の妥当性**: 01 §3.1（追加プロセス起動最小化）と 01 §7.2（シェル先行・Swift は方針確定後）の明示制約に合致。Swift をシェル呼び出しに統合すると 60 秒毎＋手動更新でプロセス起動が増えるため、(b) 現状維持＋ルール一致コメントは妥当。**評価: 妥当**。

### 9.3 重要判断の根拠（evidence_source）

| 判断内容 | evidence_source | 備考 |
| -------- | --------------- | ---- |
| 集約前後の出力が全項目一致（書式不変・最重要） | test_output | 監査者が固定入力で原コマンドと照合し全 MATCH＋printf/log 行の HEAD diff 空 |
| シェルテスト 21/21 PASS・swift build 緑 | test_output | `make test-shell` / `swift build` 実行ログ |
| 一方向依存・禁止命名不使用 | existing_code | `scripts/lib/metrics.sh` の grep 結果 |
| Swift (b) 採用の妥当性 | external_spec | 01 §3.1・§7.2 の明示制約と 02 §3.3 の比較表 |
| load raw `11.83` 維持・swap `512.00M` 維持 | test_output | 固定入力 `11.83`/`512.00M` で raw 関数が原 sed と一致 |

---

## 10. 課題と改善点

### 10.1 発見された課題

- **課題 1**: 02 §5.1 API 表に `metrics_parse_swap_raw` 欠落（指摘1・低）。
  - **影響範囲**: ドキュメント整合のみ。機能・テストは正しい。
  - **対応方法**: 02 §5.1 純粋関数行へ追記（任意・クローズ非阻害）。

### 10.2 改善提案

- **改善 1**: monitor.sh の `:-0` 二重フォールバック整理（指摘2・任意）。
  - **効果**: 軽微な可読性向上。挙動不変のため必須ではない。

---

## 11. システム仕様書の更新

### 11.1 システム仕様書の確認結果

#### 実装内容の確認

- **実装した機能**: 生メトリクス取得の `scripts/lib/metrics.sh` 集約と参照置換。
- **実装した画面**: なし（書式不変）。
- **実装したデータ構造**: なし（揮発的スカラ値のみ）。
- **実装した API**: `metrics.sh` の公開関数群（純粋 8 / ラッパ 9）。

#### システム仕様書との整合性確認

- **システム概要**: 影響なし。
- **画面設計**: 影響なし（mac-health status・Swift メニュー書式不変）。
- **データ設計**: 影響なし。
- **機能設計**: 影響なし（閾値判定経路・ログ・通知不変）。

### 11.2 システム仕様書の更新状況

#### 更新が不要な項目

- 出力書式・キー・単位・閾値経路が不変であり、システム仕様（docs/）に変更が及ばないため更新不要。

---

## 12. レビュー結果

### 12.1 総合評価

- **実装品質**: 良好（DRY 集約・単一責務・一方向依存・原コマンド完全一致）。
- **テスト品質**: 良好（UC1-S1/UC1-S2/UC2-S1 を 1 対 1 でテスト化、境界・異常系も網羅、TEST_BDD_FORMAT 準拠、副作用ゼロ）。
- **ドキュメント品質**: 良好（02 §5.1 の軽微な表追記のみ低優先で残る）。
- **総合評価**: **合格（クローズ可）**。低優先の指摘 2 件はクローズを阻害しない。

### 12.2 承認状況

- **レビュー承認者**: 検証・レビュー worker（監査者）
- **承認日**: 2026-05-28
- **承認コメント**: テスト再実行（shell 21/21 PASS・swift build 緑）と集約前後の独立出力一致（全項目 MATCH・printf/log 行 byte 一致）を確認。既存挙動・出力書式（load raw `11.83`・swap `512.00M`・docker・`?` フォールバック・monitor ログ/通知/`key:epoch`/launchd ラベル）は完全不変。DRY・単一責務・一方向依存・spec 準拠・副作用ゼロを満たす。**合格としてクローズ判定。** 差し戻しは不要。

---

## 13. 参考資料

### 13.1 プロジェクトドキュメント

- [`00_要求定義.md`](./00_要求定義.md) - 要求定義
- [`01_要件定義.md`](./01_要件定義.md) - 要件定義
- [`02_設計.md`](./02_設計.md) - 設計
- [`03_実装計画.md`](./03_実装計画.md) - 実装計画

### 13.2 その他の参考資料

- `scripts/lib/metrics.sh`、`scripts/test/metrics.bats`、`scripts/test/metrics_test.sh`、`scripts/bin/monitor.sh`、`scripts/bin/mac-health`、`src/MacHealth.swift`、`Makefile`、`README.md`
- 規約: `.agents/REVIEW_RULE.md`、`.agents/TEST_BDD_FORMAT.md`、`.agents/spec/01/02/03/06`

---

## 14. 前のステップ

- **前**: [`03_実装計画.md`](./03_実装計画.md) - 実装計画フェーズ

---

## 15. 次のステップ

- 本レビュー承認により issue クローズ（コード実装のみで完了。最終確認チェックリストはスキップ可）。

---

## 付録 A: 01 BDD ↔ 03 テスト仕様 ↔ テストコード カバレッジ対応表（map-coverage）

| 01 BDD シナリオ | 03 テスト仕様 | テストコード（bats / 自前 assert） | 結果 |
| ---- | ---- | ---- | ---- |
| UC1-S1: swap 関数が MB 整数を返す | §2.1.4 / §2.5.4（`metrics_parse_swap_mb "..512.00M.."` → `512`） | `metrics.bats`「returns integer MB」/ `metrics_test.sh` UC1-S1 | PASS |
| UC1-S2: 圧縮メモリ関数が GB を返す | §2.1.4 / §2.5.4（`metrics_parse_compressed_gb 2621440` → `10.0`） | `metrics.bats`「returns GB with 1 decimal」/ `metrics_test.sh` UC1-S2 | PASS |
| UC2-S1: mac-health と monitor.sh が同じ swap 値を得る | §2.2.4 / §2.3.4 / §2.5.4（raw/MB 整合・冪等） | `metrics.bats`「swap raw and MB are consistent」「idempotent」/ `metrics_test.sh` UC2-S1（2 ケース） | PASS |
| （追加・回帰）load raw/rounded 書式維持 | §3.1.4（mac-health raw vs monitor `%.1f`） | `metrics.bats`「load raw and rounded keep their respective formats」/ `metrics_test.sh` | PASS |
| （追加）uptime 整数除算・境界・異常系 | §2.1.3 単体 | `metrics.bats` / `metrics_test.sh`（days=2、0 pages→0.0、空入力→0） | PASS |

**結論**: 01 の全ユースケースシナリオ（UC1-S1 / UC1-S2 / UC2-S1）が 1 対 1 でテストコード化され全 PASS。テストコード化できない取得ラッパ（実コマンド実行）は実機依存のため自動化せず、固定入力の純粋関数テスト＋集約前後 diff で代替する旨が 02 §6.1 / 03 に明記されており妥当。

## 付録 B: TEST_BDD_FORMAT 準拠確認

- `metrics.bats` / `metrics_test.sh` ともファイル冒頭 doc コメントに **`ユースケース:`**、各 `@test` / 各論理ブロック直前に **`シナリオ:`** を付与。各ブロック直上に **`# Given/When/Then`**（必要箇所で `# And (Then):`）を 1 つずつ記載。3 ブロック構成・コメント直下にコード配置を満たす。**準拠: OK**。

## 付録 C: 副作用ゼロ確認

- テストは純粋パース関数のみを source して固定入力で検証。実通知・実ファイル削除・ネットワーク・実コマンド実行を伴わない。`metrics_test.sh` は破壊的副作用なしと明記。**OK**。
