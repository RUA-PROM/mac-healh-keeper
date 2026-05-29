---
document_id: "9D8C5E32-49BB-4E80-9E2B-7C3D6A8E0F11"
---

# レビュー: shallow clone ガード + README 注意書き追加

**プロジェクト名**: Mac Health Keeper
**作成日**: 2026-05-29
**branch**: `feature/20260529_shallow-clone-guard`
**parent issue**: `5D5DD113-535C-4326-82B2-74F228E2F3D5`

---

## 1. 概要

`git clone --depth=1` 等の shallow clone 環境で `install.sh` の `version_stamp.sh` が `CFBundleVersion` を `0.0.0-DEV` fallback で stamp する問題を、以下 3 段の対策で恒久解決する。

1. **README 注意書き**（当初スコープ）: install 手順節に shallow clone の影響説明と対応方法（3 通り）を callout で追記。
2. **shallow clone ガード**（**新機能・追加スコープ**）: `scripts/lib/shallow_clone_guard.sh` を新規追加。`install.sh` が swiftc ビルド直前で呼び、shallow を検出したら stderr に警告 + 推奨手順を表示。
3. **auto unshallow**（オプション）: 環境変数 `MACHEALTH_AUTO_UNSHALLOW=1` で `git fetch --tags --unshallow` を自動実行。

ユーザー指示「リファクタではなく新規機能追加」「最も安全で適切な方法で進めて」を受け、当初の「doc 変更のみ」スコープを新機能追加 posture に拡張した（00_要求定義.md §5 追補 / 03_実装計画.md タスク 4〜6）。

---

## 2. 実装内容の確認

### 2.1 新規ファイル

#### `scripts/lib/shallow_clone_guard.sh`

- 3 関数（`is_shallow_clone` / `warn_shallow_clone` / `auto_unshallow_if_requested`）と direct-exec エントリポイント。
- `set -u` のみ採用（`-e` は呼び出し側を巻き込まないため不採用）。02_設計 §3.2.5 準拠。
- 02 §3.2.4 の固定 stderr フォーマット契約を厳守。
- `.git/shallow` 存在 → `git rev-parse --is-shallow-repository` の優先順位で判定（02 §3.2.3）。

#### `scripts/test/shallow_clone_guard_test.sh`

- `launchagent_lifecycle_test.sh` と同流儀の自前 assert ヘルパ。
- 一時 `git init --bare` ＋ `file://` プロトコルでの `--depth=1 clone` で実 shallow を再現（ローカルパス clone では `--depth=1` が無視される git の挙動を踏まえた実装）。
- ファイル冒頭に `ユースケース:` doc コメント、各シナリオ直前に `シナリオ:` doc コメント、各ブロック直上に `Given:` / `When:` / `Then:` / `And (Then):` を記載（`.agents/TEST_BDD_FORMAT.md` §1/§2/§3 準拠）。

### 2.2 既存ファイル更新

- `install.sh`: §4.5 として guard 呼び出し 1 ブロックを追加（`|| true` で囲みビルドを止めない）。
- `README.md`: install 手順節に callout を追加（shallow / `git fetch --tags --unshallow` / `MACHEALTH_AUTO_UNSHALLOW` を必ず明記）。
- `Makefile`: `test-shell` のフォールバックランナーに `shallow_clone_guard_test.sh` を追加。

---

## 3. 設計・境界の確認

- 既存 `scripts/lib/version_stamp.sh` の挙動は **無変更**（fallback `0.0.0-DEV` 維持）。
- 新ライブラリは単一責務「shallow 検出と警告」のみで、ビルド・配置・stamp とは独立。
- `install.sh` 統合は 1 ブロック追加のみで既存 LaunchAgent ライフサイクル等への副作用なし。
- shellcheck 警告 0、source 循環なし、security-scan クリア。

---

## 4. テスト結果

### 4.1 `make check` 結果（4.1）

```
==> lint-shell        OK
==> lint-shfmt        SKIP (任意・未導入)
==> lint-swift-format SKIP
==> lint-swiftlint    SKIP
==> check-cycles      OK ([INFO] source 依存に循環は検出されませんでした)
==> security-scan     OK ([INFO] セキュリティパターンの検出はありません)
==> test              OK
    - swift run MacHealthCheck: OK (pure-core BDD)
    - swift test: OK
    - shell tests (新規 shallow_clone_guard_test 含む): OK
==> all checks passed
```

### 4.2 新規シェルテストサマリ

```
shallow_clone_guard_test: 29 passed, 0 failed
```

#### カバレッジ（01_要件定義.md BDD UC との対応）

| UC | シナリオ | 対応 assertion | 結果 |
|---|---|---|---|
| UC3-S1 | 通常 clone で警告なし | UC3-S1 関数判定 / 直接実行 exit / 静音 stderr / 静音 stdout | 全 PASS |
| UC3-S2 | shallow clone で警告 + 推奨手順 | shallow 判定 / exit 0 / 4 種固定文言 grep（"shallow clone detected" / "CFBundleVersion may fall back to 0.0.0-DEV" / "git fetch --tags --unshallow" / "MACHEALTH_AUTO_UNSHALLOW=1"） | 全 PASS |
| UC3-S3 | AUTO unshallow | exit 0 / "attempting" ログ / "auto unshallow succeeded" ログ / 再判定で非 shallow / warn_shallow_clone 単体契約 / AUTO 未指定で no-op / 既 full で短絡 | 全 PASS |
| UC4-S1 | 引数欠落 | exit 2 / Usage stderr | 全 PASS |
| UC4-S2 | `.git` 不在 / 存在しないパス | exit 0 / "not a git repository" / shallow 警告は出ない | 全 PASS |

---

## 5. 受け入れ基準の確認（00_要求定義.md §6）

| 基準 | 内容 | 結果 |
|---|---|---|
| 基準 1 | README.md に shallow clone 注意書き | OK（`grep -nE 'shallow\|--unshallow\|MACHEALTH_AUTO_UNSHALLOW' README.md` で 7 件ヒット） |
| 基準 2 | shallow clone で guard を呼ぶと stderr に警告 + 推奨手順 | OK（§6.2 ログ参照） |
| 基準 3 | `MACHEALTH_AUTO_UNSHALLOW=1` で auto unshallow | OK（§6.3 ログ参照） |
| 基準 4 | 通常 clone で警告が出ず exit 0 | OK（§6.1 ログ参照） |
| 基準 5 | `make check` 緑 + テスト 12 件以上 | OK（29 件 PASS） |
| 基準 6 (実機検証) | エビデンスを 04_review/memo に記録 | 本ファイル §6 で対応 |

---

## 6. 実機検証ログ（受け入れ基準ルール §3.2–3.4）

### 6.1 通常 clone での非警告（main repo に対して）

```bash
$ bash scripts/lib/shallow_clone_guard.sh "$REPO_DIR"
$ echo "exit=$?"
exit=0
```

stderr 出力なし。

### 6.2 shallow clone での警告（file:// 経由で main repo を `--depth=1` clone）

```bash
$ git clone --quiet --depth=1 "file://$REPO_DIR/.git" /tmp/mhk-shallow
$ git -C /tmp/mhk-shallow rev-parse --is-shallow-repository
true
$ bash scripts/lib/shallow_clone_guard.sh /tmp/mhk-shallow
[shallow_clone_guard] WARN: shallow clone detected at /tmp/mhk-shallow
[shallow_clone_guard] WARN: CFBundleVersion may fall back to 0.0.0-DEV (git describe cannot find tags)
[shallow_clone_guard] hint: run `git fetch --tags --unshallow` before ./install.sh
[shallow_clone_guard] hint: or re-run with MACHEALTH_AUTO_UNSHALLOW=1 to auto-recover
$ echo "exit=$?"
exit=0
```

### 6.3 `MACHEALTH_AUTO_UNSHALLOW=1` で自動回復

```bash
$ MACHEALTH_AUTO_UNSHALLOW=1 bash scripts/lib/shallow_clone_guard.sh /tmp/mhk-shallow
[shallow_clone_guard] INFO: MACHEALTH_AUTO_UNSHALLOW=1, attempting `git fetch --tags --unshallow`
[shallow_clone_guard] INFO: auto unshallow succeeded
$ echo "exit=$?"
exit=0
$ git -C /tmp/mhk-shallow rev-parse --is-shallow-repository
false
$ bash scripts/lib/shallow_clone_guard.sh /tmp/mhk-shallow
$ echo "exit=$?(再実行)"
exit=0(再実行)
```

### 6.4 fallback への影響再現（合成 repo で tag 不在 + shallow）

main repo は HEAD のコミット自体がリリース tag `v20260529.210908` と一致するため shallow でも `git describe` が短縮 SHA ではなく tag を返してしまい純粋な fallback は再現しない。tag 不在の HEAD を持つ合成 repo で再現:

```bash
$ # commit1(+tag v9.9.9) → commit2 → commit3 の repo を作って --depth=1 clone
$ git -C shallow describe --tags --always
21bea3d           # ← tag が無いため短縮 SHA。これが version_stamp 経路に渡ると CFBundleVersion になる
$ bash scripts/lib/shallow_clone_guard.sh shallow
[shallow_clone_guard] WARN: shallow clone detected at /tmp/.../shallow
[shallow_clone_guard] WARN: CFBundleVersion may fall back to 0.0.0-DEV (git describe cannot find tags)
[shallow_clone_guard] hint: run `git fetch --tags --unshallow` before ./install.sh
[shallow_clone_guard] hint: or re-run with MACHEALTH_AUTO_UNSHALLOW=1 to auto-recover
```

> 補足: 実 main repo は最新コミットが tag と一致しているため shallow でも `git describe` が tag を返す状況だが、これは「将来 tag から離れた HEAD で shallow clone するユーザー」（典型: CI / 最新の develop branch ユーザー）に対する予防策として guard は機能する。

### 6.5 `install.sh` 構文 + guard 呼び出し部の検証

```bash
$ bash -n install.sh && echo "install.sh syntax OK"
install.sh syntax OK
$ grep -nE "shallow_clone_guard|MACHEALTH_AUTO_UNSHALLOW" install.sh
76:# === 4.5 shallow clone ガード（CFBundleVersion fallback 警告）===
77:# issue: 20260529_123513_README_shallow_clone注意書き追加
...
84:echo "▶ shallow clone ガード（CFBundleVersion fallback 警告）"
85:bash "$REPO_DIR/scripts/lib/shallow_clone_guard.sh" "$REPO_DIR" || true
```

### 6.6 副作用観点

- `version_stamp.sh` は無変更（fallback 値 `0.0.0-DEV` も保持）。
- `install.sh` は 1 ブロック追加のみで既存ステップの順序・内容は不変。
- LaunchAgent 関連は無変更（PR #6 で追加した `launchagent_lifecycle.sh` の挙動と独立）。
- shellcheck warning 0、source 循環なし、security-scan クリア。

### 6.7 GUI 目視確認の依頼（ユーザー側）

本 issue は CLI 完結のため GUI 目視確認は不要。
ただし将来、新たな端末で `git clone --depth=1` → `./install.sh` を実行した際に:

- stderr に `[shallow_clone_guard] WARN: ...` 4 行が表示されること
- 終了コード 0 でビルド継続すること
- `MACHEALTH_AUTO_UNSHALLOW=1 ./install.sh` で auto unshallow ログが表示され、`CFBundleVersion` が tag 由来になること

を確認可能。

### 6.8 既知の制約

- main repo の最新コミットがリリース tag と一致している場合（典型: PR merge 後の自動 release）shallow clone でも `git describe` が tag を返すため fallback は出ない。これは guard の責務外（責務は shallow 状態の可視化）。
- `git fetch --tags --unshallow` 自体が失敗するケース（オフライン環境 / origin URL の解決失敗等）は guard が WARN ログを残しビルドを継続する設計（02 §3.2.5）。

---

## 7. 変更ファイル一覧

| 種別 | パス |
|---|---|
| 新規 | `scripts/lib/shallow_clone_guard.sh` |
| 新規 | `scripts/test/shallow_clone_guard_test.sh` |
| 更新 | `install.sh` |
| 更新 | `README.md` |
| 更新 | `Makefile` |
| 更新 | `.workflow/20260529_123513_README_shallow_clone注意書き追加/00_要求定義.md` |
| 更新 | `.workflow/20260529_123513_README_shallow_clone注意書き追加/01_要件定義.md` |
| 更新 | `.workflow/20260529_123513_README_shallow_clone注意書き追加/02_設計.md` |
| 更新 | `.workflow/20260529_123513_README_shallow_clone注意書き追加/03_実装計画.md` |
| 新規 | `.workflow/20260529_123513_README_shallow_clone注意書き追加/memo/20260529_213631_verify-and-close.md` |
| 新規 | `.workflow/20260529_123513_README_shallow_clone注意書き追加/04_review.md`（本ファイル） |

---

## 8. 残課題

- なし。基準 1〜6 を満たしている。
- 将来課題（任意）: `install.sh` 統合の smoke test を `version_stamp_test.sh` 並みに追加すると、guard 呼び出し部の文法・順序回帰検知が強化できる。

---

## 9. 参考資料

- [`./00_要求定義.md`](./00_要求定義.md)
- [`./01_要件定義.md`](./01_要件定義.md)
- [`./02_設計.md`](./02_設計.md)
- [`./03_実装計画.md`](./03_実装計画.md)
- [`./memo/20260529_213631_verify-and-close.md`](./memo/20260529_213631_verify-and-close.md)
- [`../../.agents-project/受け入れ基準ルール.md`](../../.agents-project/受け入れ基準ルール.md) §3.2–3.4
- [`../../.agents/TEST_BDD_FORMAT.md`](../../.agents/TEST_BDD_FORMAT.md) §0/§1/§2/§3
