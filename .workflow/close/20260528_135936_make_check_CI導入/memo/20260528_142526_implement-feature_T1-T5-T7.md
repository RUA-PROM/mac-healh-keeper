# implement-feature 実装証跡（T1〜T5・T7）

**対象 issue**: `.workflow/20260528_135936_make_check_CI導入/`
**実施日時**: 2026-05-28 14:25:26（JST）
**実施者**: implement-feature サブエージェント
**command**: `implement-feature`（skill chain: implement-change → refactor-safely[省略]）

> **位置付け**: 実装フェーズの作業証跡 memo。03_実装計画.md §2 の T1〜T5・T7 のローカル実証ログをまとめる。T6（実 PR で AT1〜AT6 実機実証）は本フェーズの対象外（merge 前のため verify-and-close / PR 作成以降に持ち越し）。

---

## 0. 事前確認

- `.agents-project/` は README のみで実質空（`.agents/` 標準ルールに従う）。
- 委譲パケットの確定 YAML（02_設計 §4.1）に従って実装する。
- 軽微指摘 N-3（`concurrency.group` を簡素化するか）は本実装フェーズで判断する。

---

## 1. N-3 判断（concurrency.group の値）

**決定**: 02_設計 §4.1 / §3.4.2 の `check-${{ github.workflow }}-${{ github.ref }}` を**そのまま採用**する。

**根拠**:

- GitHub Actions 公式ドキュメント（[Using concurrency](https://docs.github.com/actions/using-jobs/using-concurrency)）の典型例と一致。
- 将来 workflow ファイルが増えた際の衝突回避性が高い（同一 ref でも workflow ごとに独立した group）。
- 簡素化（`check-${{ github.ref }}`）のメリットは可読性のわずかな向上のみで、コスト・リスクの差分はほぼゼロ。
- AI フレンドリー設計（02 §1.2）でも「YAML を一読すれば挙動が把握できる粒度」を維持できており、簡素化の必要性は低い。

**結果**: 02_設計 §3.4.2 / §4.1 の更新は**不要**。

---

## 2. T1: `.github/workflows/check.yml` の新規作成

### 2.1 作業内容

- `.github/workflows/` ディレクトリを新規作成。
- `.github/workflows/check.yml` を新規作成。内容は 02_設計 §4.1 の確定 YAML と一致（LF 改行・スペース 2 個インデント）。

### 2.2 成果物

- 新規ファイル: `.github/workflows/check.yml`（38 行・改行 LF）
- トップキー: `name`, `on`, `permissions`, `concurrency`, `jobs`
- `jobs.check.runs-on: macos-latest`、`timeout-minutes: 30`、3 step（Checkout / Ensure shellcheck / Run make check）

---

## 3. T2: YAML 構文確認

### 3.1 `python3 yaml.safe_load`

```python
import yaml
with open(".github/workflows/check.yml") as f:
    d = yaml.safe_load(f)
# PyYAML は YAML 1.1 互換で bare key "on" を True にキャストする（Norway problem 系）。
# GitHub Actions は YAML 1.2 互換で正しく "on" として解釈するため検証側で正規化。
if True in d and "on" not in d:
    d["on"] = d.pop(True)
```

**結果**: 例外なく parse 成功。

- raw top keys: `['name', True, 'permissions', 'concurrency', 'jobs']`
- step names: `['Checkout repository', 'Ensure shellcheck', 'Run make check']`
- on keys: `['pull_request', 'push']`
- permissions: `{'contents': 'read'}`
- concurrency.group: `check-${{ github.workflow }}-${{ github.ref }}`
- concurrency.cancel-in-progress: `True`
- 必須キー（name / on / permissions / concurrency / jobs.check.{runs-on, steps, timeout-minutes}）すべて存在。
- runs-on == macos-latest、timeout-minutes == 30、steps 数 == 3。

> 注: PyYAML が `on` を `True` にキャストする件は GitHub Actions の挙動には影響しない（YAML 1.2 では正しく `"on"` のまま）。`actionlint` でも正常 parse される（§3.2）。

### 3.2 `actionlint`

```
$ actionlint .github/workflows/check.yml
$ echo $?
0
```

**結果**: 警告・エラーなし、exit 0。

---

## 4. T3: ローカル `make check` 緑確認

```
$ make check >/tmp/mkcheck.log 2>&1; echo "exit=$?"
exit=0
$ tail -3 /tmp/mkcheck.log
==> all tests passed
    test: OK
==> all checks passed
```

**結果**: exit 0、最終行 `==> all checks passed`。AT3 のローカル前提を満たす。

---

## 5. T4: shellcheck フォールバック step の分岐確認

### 5.1 検証スクリプト

`.github/workflows/check.yml` の `Ensure shellcheck` step 本体ロジックをローカル bash に落としこんで実行。`brew install` は安全のため mock コメント化（実 install しない）。

### 5.2 Case 1: PATH に shellcheck 無し（`PATH=/usr/bin:/bin`）

```
$ PATH=/usr/bin:/bin bash -c "$script"
shellcheck not found; installing via Homebrew
$ echo $?
0
```

**結果**: not-found 分岐に入り exit 0。AT5 のローカル前段を満たす。

### 5.3 Case 2: PATH に shellcheck 有り（current PATH）

```
$ bash -c "$script"
shellcheck already available
$ echo $?
0
```

**結果**: already-available 分岐に入り exit 0。AT6 のローカル前段を満たす。

> 注: 初回 `env -i PATH=/usr/bin:/bin bash -c ...` が exit 139（SIGSEGV）を返したため、`PATH=/usr/bin:/bin bash -c ...` に切り替えて再実行。`env -i` で `HOME` 等まで消した状態の bash 起動エラーであり、Ensure shellcheck ロジックそのものの不具合ではない。

---

## 6. T5: AT4 ローカル実証（`__force_fail.sh` 注入 → 復元）

### 6.1 注入手順（Edit ツールで安全に手動編集 — N-5 採用）

1. `scripts/test/__force_fail.sh` を新規作成（`#!/usr/bin/env bash\nexit 1\n`）。
2. `Makefile` の `test-shell` ターゲットの fallback 行末尾に `&& bash scripts/test/__force_fail.sh` を**追記**：
   - 旧: `bash scripts/test/monitor_test.sh && bash scripts/test/metrics_test.sh && bash scripts/test/log_rotate_test.sh; \`
   - 新: `bash scripts/test/monitor_test.sh && bash scripts/test/metrics_test.sh && bash scripts/test/log_rotate_test.sh && bash scripts/test/__force_fail.sh; \`

### 6.2 注入後の `make check` 実行（CI 赤シナリオ）

```
$ make check >/tmp/mkcheck_fail.log 2>&1; echo "exit=$?"
exit=2
$ tail -10 /tmp/mkcheck_fail.log
  ok   - A regression: should_notify returns 1 when cooldown not elapsed (with lock)

log_rotate tests: 15 passed, 0 failed
make[2]: *** [test-shell] Error 1
    shell tests: FAILED
==> some tests failed
make[1]: *** [test] Error 1
    test: FAILED
==> some checks failed
make: *** [check] Error 1
```

**結果**: exit 2（非 0）、ログに `==> some checks failed` を含む。**AT4 のローカル実証 OK**。

### 6.3 復元

1. `Makefile` の追記を元に戻す（Edit ツールで `&& bash scripts/test/__force_fail.sh` を削除）。
2. `rm -f scripts/test/__force_fail.sh`。

### 6.4 復元確認

```
$ grep -n "__force_fail" Makefile
(空: 痕跡なし)
$ test ! -f scripts/test/__force_fail.sh && echo "[OK] __force_fail.sh は存在しない"
[OK] __force_fail.sh は存在しない
$ sed -n '64,72p' Makefile
test-shell:
	@echo "==> shell tests"
	@if command -v bats >/dev/null 2>&1; then \
		echo "    (using bats)"; \
		bats scripts/test/; \
	else \
		echo "    (bats not found -> fallback to self-made assert runner)"; \
		bash scripts/test/monitor_test.sh && bash scripts/test/metrics_test.sh && bash scripts/test/log_rotate_test.sh; \
	fi
```

`git diff Makefile` の現在の差分は**すべて先行 issue `.workflow/20260528_121550_make_check導入/` 由来**（test 集約コメント・check ターゲットの追加等）であり、本 T5 の一時注入による差分は残存していない（grep で確認）。

### 6.5 復元後の再緑確認

```
$ make check >/tmp/mkcheck_restored.log 2>&1; echo "exit=$?"
exit=0
$ tail -3 /tmp/mkcheck_restored.log
==> all tests passed
    test: OK
==> all checks passed
```

**結果**: exit 0、最終行 `==> all checks passed`。**復元完全性 OK**。

---

## 7. T7: README の CI 言及判断と反映

### 7.1 判断

- バッジ追加: **行わない**（00 §5 で明示除外）。
- 1〜2 行の CI 言及追記: **採用**。

### 7.2 根拠

- 00 §5 の除外対象は「ステータスバッジ」のみで、CI 連携への言及は除外対象外。
- 既存 README §ローカル検証 が `make check` を中心に整理されており、CI で同等の `make check` が走る旨を 1〜2 行で補足することで、開発者の認知負荷を下げられる（PR で何が走るかが README から辿れる）。

### 7.3 追記内容

`README.md §ローカル検証` の `make check はいずれかの検証が失敗すると非 0 で終了します。` の直後に以下を追記：

```
PR / main push 時には GitHub Actions（`.github/workflows/check.yml`）が同じ `make check` を `macos-latest` runner で自動実行します。runner に `shellcheck` が同梱されていない場合は `brew install shellcheck` がフォールバックで走ります。
```

Markdown 見出し構造は変更なし。`.github/workflows/check.yml` への相対リンクのみ追加。

---

## 8. 変更ファイル一覧（本フェーズ）

- **新規**: `.github/workflows/check.yml`（38 行・T1 成果物）
- **更新**: `README.md`（T7: §ローカル検証に 1 段落追記）

> 上記以外の `git status` 差分（`Makefile`, `scripts/test/metrics_test.sh`, `scripts/bin/monitor.sh`, `scripts/config/thresholds.sh`, `scripts/lint/` 配下、`.workflow/20260528_121550_make_check導入/`）は**先行 issue 由来の未コミット差分**で、本フェーズの対象外。

---

## 9. DoD 確認（implement-feature command）

| DoD 項目 | 結果 |
| --- | --- |
| 実装計画（03 §2 T1〜T5・T7）に従い実装されている | OK |
| YAML 構文 OK（python yaml + actionlint） | OK（§3） |
| `make check` 0 終了（ローカル）| OK（§4・§6.5） |
| T5 AT4 実証で「注入 → 非 0 → 復元 → 再 0」を確認 | OK（§6） |
| Makefile / scripts/test の T5 一時改変が**完全に元に戻っている** | OK（§6.4 grep / ls） |
| 一時改変・`__force_fail.sh` を**コミットしていない** | OK（git add していない） |
| 証跡 memo を YYYYMMDD_HHMMSS_ プレフィックスで作成 | OK（本ファイル） |
| 単体テスト観点 | check.yml 自体に追加コードなし。YAML parse・分岐検証・AT4 注入再現で対応（§3 / §5 / §6） |

---

## 10. 次フェーズ（verify-and-close）への引き継ぎ

- **T6（実 PR で AT1〜AT6 実機実証）は本フェーズで実行していない**。理由: 本ブランチ `feature/20260528` 上で `.github/workflows/check.yml` を実コミット・push する前は GitHub Actions が発火しないため、PR 作成 / verify-and-close フェーズ以降に持ち越す。
- AT1〜AT3, AT5, AT6 は実 PR の Actions ログ取得 → 04_review §3 に `test_output` として貼り付け。
- AT4 は本 memo §6 のローカル証跡（注入 → 非 0 → 復元 → 再 0）で先行 issue と同型に実証済み。実 PR 側での AT4 実証は 04_review 作成時に判断（実コミットへの注入はリスクが高いため、ローカル実証で代替する選択肢を 04_review §6 監査で記載すること）。
- 軽微指摘 N-4（00 §1.1 の目的文 50 字超過）は本フェーズで対応していない。実装フェーズで合わせて見直す余地としていたが、判定可能性に影響しないため verify-and-close 側で再判断。
- 軽微指摘 N-3（concurrency.group）は本フェーズで「設計通り維持」と判断済み（§1）。02_設計 の更新不要。
