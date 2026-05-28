---
document_id: "0BC27236-E1AE-4D58-A006-4792B848DAA4"
---

# memo: 修正A（指摘 I-1）`make test` の CLT 環境フォールバック対応

**対象 issue**: サブ A テスト・ビルド基盤の確立
**対応する指摘**: 04_review.md §4.3 指摘 I-1（`make test` が CLT 環境で `test-shell` に到達しない）
**実行モード**: quick（小修正＋証跡 memo）
**作成日時（JST）**: 2026-05-28 11:10:49（プレフィックスは `TZ=Asia/Tokyo date +%Y%m%d_%H%M%S` 実行で取得）

---

## 1. 背景・問題

旧 `Makefile` の `test` ターゲットは `test: test-swift test-shell` で、先頭 `test-swift`（=`swift test`）が
本環境（full Xcode 非導入・Command Line Tools のみ）で `error: no such module 'XCTest'` により失敗すると、
Make が即停止して `test-shell` に到達しない（`make: *** [test-swift] Error 1`）。
そのため CLT 環境では単一コマンド `make test` でシェルテストの合否が得られなかった（00 §6 / 01 §3.3 の「単一コマンドでテスト実行」が full Xcode 前提に限定）。

## 2. 修正内容

`Makefile` の `test` ターゲットを書き換え、次の挙動にした（`test-swift`/`test-shell` 単体ターゲットは従来どおり温存）。

- `xcrun --find xctest` で XCTest 利用可否を判定する。
  - **利用可能な環境**: `swift test` を実行し、失敗したら集約終了コード `rc=1` に反映（全体失敗）。
  - **非搭載環境（CLT のみ等）**: 警告を stderr に出して `swift test` を **skip**（rc に影響させない）。
- 上記いずれの場合も `$(MAKE) test-shell` を**必ず実行**し、失敗したら `rc=1` に反映。
- 最後に `exit $$rc` で集約終了コードを返す（いずれか失敗で非0、全成功＝XCTest skip + シェル成功で 0）。

`test-shell` は変更なし（bats 利用可なら bats、不在なら自前 assert ランナーで monitor/metrics/log_rotate を実行）。

## 3. 検証結果（本環境＝CLT のみ・bats 未インストール）

| コマンド | 結果 | 備考 |
| --- | --- | --- |
| `xcrun --find xctest` | not found | CLT 環境のため XCTest 非搭載を確認 |
| `make test-shell` | **monitor 9 / metrics 17 / log_rotate 15 = 全 41 PASS, 0 failed**（exit 0） | 回帰なし。従来挙動を維持 |
| `make test` | **swift test を SKIP（警告表示）→ test-shell 41 PASS → `==> all tests passed`（exit 0）** | CLT でもシェルテストが走り結果が出ることを確認 |
| 集約終了コード検証（test-shell が失敗する模擬 Makefile） | **exit 2（非0）** | いずれか失敗で全体非0 を確認 |

- 「振る舞い不変」: テスト実行性の改善のみ。アプリ挙動・既存テストのロジック・合否は変えていない。
- XCTest 利用可能環境では `swift test` の失敗が全体失敗に反映される設計のため、full Xcode 環境での緑化判定も保たれる。

## 4. 変更ファイル

- `Makefile`（`test` ターゲットのみ書き換え。`test-swift`/`test-shell` は温存）

## 5. 自己判定

指摘 I-1 対応完了・回帰なし。
