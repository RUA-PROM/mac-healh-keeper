---
document_id: "1A981088-1753-404E-BEB0-A9CA1F952410"
issue_id: "3D667BE0-934D-4FC6-B7D0-C423CF45B03F"
---

# レビュー: CI（GitHub Actions）でバージョン stamp する B 案の実装

**プロジェクト名**: Mac Health Keeper / CI stamp B 案
**作成日**: 2026 年 05 月 29 日
**最終更新**: 2026 年 05 月 29 日
**実装ブランチ**: `feature/20260529_ci-release-stamp`
**ベース commit**: `553d411`（main）

---

## 1. 実装内容の確認

### 1.1 採用方針（新規機能追加 posture）

> 当初 02 で「create-release.yaml を macos-latest 化する破壊的変更」を想定していたが、実装フェーズでは「**新規ワークフロー `release-app.yml` 追加 + 既存最小修正**」に切り替えた。理由は次の 2 点。
>
> - 既存 `create-release.yaml`（ubuntu-latest）の挙動を破壊するリスクが大きい（tag 命名規約・concurrency group・gh release create 経路）
> - 役割分離（tag 生成 = ubuntu / artifact 添付 = macos）の方が CI ログの可読性と部分的 retry の容易性が高い

### 1.2 追加・変更ファイル一覧

| 区分 | パス | 役割 |
|---|---|---|
| 新規 workflow | `.github/workflows/release-app.yml` | macos-latest で `.app` を組み立て、Release artifact として添付 |
| 既存 workflow（最小修正） | `.github/workflows/create-release.yaml` | tag 生成後に `gh workflow run release-app.yml` を 1 行 dispatch |
| 新規 lib | `scripts/lib/release_artifact_validator.sh` | `.app` zip の Info.plist 必須キー / CFBundleVersion 一致 / バイナリ存在を検証 |
| 新規 test | `scripts/test/release_artifact_validator_test.sh` | validator の BDD 単体テスト（**34 ケース**） |
| 新規 test | `scripts/test/workflow_release_app_test.sh` | release-app.yml / create-release.yaml / check.yml の構造テスト（**27 ケース**、YAML 構文 lint 含む） |
| 新規 test | `scripts/test/ci_release_smoke_test.sh` | ローカル macOS で CI 全フロー擬似実行（**13 ケース**、`make test-shell` には組み込まず手動実行） |
| 既存 Makefile（最小修正） | `Makefile` | `test-shell` ターゲットに validator test と workflow test を追加 |
| ドキュメント追補 | `00_要求定義.md` / `02_設計.md` / `03_実装計画.md` | 「新規機能追加 posture」への方針切替を反映 |

### 1.3 設計判断のハイライト

- **release-app.yml の trigger は `push: tags ['v*']` + `workflow_dispatch`**。`GITHUB_TOKEN` で push された tag は他 workflow を起動しない制約があるため、`create-release.yaml` 側から `gh workflow run release-app.yml --field tag=<TAG>` で明示 dispatch する経路を採用。
- **artifact 検証は CI と同じスクリプト** `scripts/lib/release_artifact_validator.sh` を CI からもローカルからも呼ぶ。pure-shell + PlistBuddy + unzip のみで実装し、AppBundlePolicy.requiredInfoPlistKeys と同期する必須キー集合を持つ。
- **shallow clone fallback の検知**: validator は `CFBundleVersion = 0.0.0-DEV` を WARN として stdout に出す（期待値未指定時は exit 0）。CI 側では期待値（CFBundleVersion ENV）を渡して厳格化し、fetch-depth 漏れを即検知する。
- **`make package` の zip コマンド**: 02 では `ditto -c -k --sequesterRsrc --keepParent` を想定していたが、Issue B（PR #8）が既に `zip -r -q` で `make package` を確立しており、本 issue で再実装するのはスコープ外と判断（差分最小化）。

---

## 2. 設計・境界の確認

- **境界**: `create-release.yaml`（tag 生成・Release 作成 / ubuntu） / `release-app.yml`（.app 組み立て・添付 / macos）/ `validator.sh`（artifact 品質判定 / pure-shell）の **3 責務に分離**。各々独立して fail し得るが、互いを破壊しない。
- **既存ワークフローへの影響**:
  - `check.yml`: **無変更**（テストで監視）
  - `create-release.yaml`: **2 step 追加のみ**（`id: create_tag` + `gh workflow run` step）。runs-on / tag 命名 / gh release create の振る舞いは不変
- **AppBundlePolicy.requiredInfoPlistKeys（Swift pure-core）との整合**: validator.sh の `required_keys` 変数で同じ 6 キー集合を参照。Swift 側を編集した場合は本スクリプトも同期する旨を `release_artifact_validator.sh` のコメントに明示。

---

## 3. テスト結果

### 3.1 `make check`（CI と同等）

```
==> all checks passed
```

詳細:

- `lint-shell` (shellcheck 0.11.0): OK
- `lint-shfmt`: SKIP（任意ツール未導入）
- `lint-swift-format`: SKIP
- `lint-swiftlint`: SKIP
- `check-cycles`: OK
- `security-scan`: OK
- `swift run MacHealthCheck` (pure-core BDD): OK
- `swift test` (XCTest): OK
- `test-shell`:
  - monitor_test: OK
  - metrics_test: OK
  - log_rotate_test: OK
  - install_metrics_smoke_test: OK
  - version_stamp_test: OK
  - launchagent_lifecycle_test: OK
  - plist_validator_test: OK
  - launchagent_doctor_test: OK
  - shallow_clone_guard_test: 29 passed, 0 failed
  - build_app_bundle_test: 38 passed, 0 failed
  - **release_artifact_validator_test: 34 passed, 0 failed**（新規）
  - **workflow_release_app_test: 27 passed, 0 failed**（新規）

### 3.2 CI 一気通貫の擬似実行（`ci_release_smoke_test.sh`）

```
==> make clean (前準備)
==> make build
  ok   - UC1-S1: make build が終了コード 0
  ok   - UC1-S1: build/MacHealth.app ディレクトリ存在
  ok   - UC1-S1: バイナリ存在
  ok   - UC1-S1: Info.plist 存在
==> make package
  ok   - UC1-S1: make package が終了コード 0
  ok   - UC1-S1: zip 生成済み (.../build/MacHealth-v20260529.210908-2-g553d411.zip)
  ok   - UC1-S1: validator が終了コード 0
  ok   - UC1-S1: validator OK サマリ
==> make clean-app
  ok   - UC2-S1: build/MacHealth.app が削除された
  ok   - UC2-S1: build/MacHealth バイナリは温存
==> make clean
  ok   - UC3-S1: build/ ディレクトリが削除された
  ok   - UC4-S1: 0.0.0-DEV + 期待値（tag）で validator が NG
  ok   - UC4-S1: mismatch メッセージで shallow clone 検知

ci_release_smoke_test: 13 passed, 0 failed
```

---

## 4. 実機検証ログ（`.agents-project/受け入れ基準ルール.md` §3.2-3.4）

### 4.1 環境

- 端末: ローカル macOS（Darwin 24.6.0）
- リポジトリ: `/Volumes/ssd-01/NextCloud/Documents/各案件管理/builtfunc/mac-health-keeper`
- ブランチ: `feature/20260529_ci-release-stamp`
- HEAD: `553d411` 基準（feature branch 上の追加 commit は後述）
- `git describe --tags --always`: `v20260529.210908-2-g553d411`

### 4.2 CI 擬似実行（ローカルで全フロー再現）

```bash
make clean
make build        # 終了コード 0、所要 ~6.4 秒
make package      # 終了コード 0、build/MacHealth-v20260529.210908-2-g553d411.zip 生成（95,485 bytes）
bash scripts/lib/release_artifact_validator.sh \
  build/MacHealth-v20260529.210908-2-g553d411.zip \
  "$(git describe --tags --always)" \
  "$(pwd)"
```

validator 出力（抜粋）:

```
  OK   - Contents/Info.plist exists
  OK   - Contents/MacOS/ directory exists
  OK   - Contents/MacOS/MacHealth exists
  OK   - Contents/MacOS/MacHealth is executable
  OK   - Info.plist key 'CFBundleExecutable' = 'MacHealth'
  OK   - Info.plist key 'CFBundleIdentifier' = 'com.github.adachi-tatsuru.machealth.app'
  OK   - Info.plist key 'CFBundleName' = 'Mac Health'
  OK   - Info.plist key 'CFBundlePackageType' = 'APPL'
  OK   - Info.plist key 'CFBundleVersion' = 'v20260529.210908-2-g553d411'
  OK   - Info.plist key 'CFBundleShortVersionString' = '1.3'
  OK   - CFBundleVersion matches expected (v20260529.210908-2-g553d411)
  OK   - CFBundleExecutable 'MacHealth' aligns with MacOS/MacHealth
release_artifact_validator: OK
```

### 4.3 受け入れ基準ごとの判定

| 基準 | 内容 | 判定 |
|---|---|---|
| 基準 1 | tag を打って `create-release.yaml` が成功すると Release に `MacHealth-<tag>.app.zip` が upload | **GUI 観測待ち**（merge 後の post-merge CI で実観測） |
| 基準 2 | DL した artifact の `CFBundleVersion` が tag 値（または `git describe` 値）と一致 | **OK**（ローカル make build → make package → validator で同 commit から決定的に確認） |
| 基準 3 | A 案 install.sh stamp の挙動は変わらない（後方互換） | **OK**（install.sh 未変更。`scripts/test/version_stamp_test.sh` 緑、`build_app_bundle_test` 緑） |
| 基準 4 | `make check` が緑のまま維持 | **OK**（all checks passed） |
| 基準 5 | ローカル環境で artifact 検証エビデンスを残す | **OK**（本 §4.2 / 4.3） |

### 4.4 副作用の確認

- 既存テスト（`monitor_test` / `metrics_test` / `version_stamp_test` / `launchagent_*` / `build_app_bundle_test` 等）に**回帰なし**。
- `install.sh` / `uninstall.sh` は**変更なし**。
- `check.yml` は**変更なし**（テスト UC3 で監視）。
- `create-release.yaml` の `runs-on` / tag 命名規約は**不変**（テスト UC2 で監視）。

---

## 5. GUI / post-merge 目視確認の依頼

CLI から自動検証できない以下は **merge 後にユーザー側または post-merge CI 観測**で確認をお願いします。

1. **post-merge CI**: main マージ後、`create-release.yaml` が tag を作成し、その直後に `gh workflow run release-app.yml` が dispatch され、macos-latest で `.app` が組み立てられて Release に `MacHealth-<tag>.zip` が添付されること。
2. **Release ページ目視**: `gh release view <tag>` または GitHub web UI で artifact が添付されていること。
3. **artifact DL → 実起動**: 添付された zip を実機で DL → unzip → Gatekeeper 回避（`xattr -dr com.apple.quarantine`）→ 起動できること（メニューバーに 🩺 アイコン）。

---

## 6. 残課題

- 署名・公証は対象外（00 §5 除外要件のまま）。
- Universal Binary は別 issue。
- post-merge CI の実観測は本 issue のスコープに含む（§5.1）が、artifact DL → 起動の目視は GUI 依存。

---

## 7. 参考資料

- [`00_要求定義.md`](./00_要求定義.md)
- [`01_要件定義.md`](./01_要件定義.md)
- [`02_設計.md`](./02_設計.md)
- [`03_実装計画.md`](./03_実装計画.md)
- [`memo/20260529_223709_verify-and-close.md`](./memo/20260529_223709_verify-and-close.md)
- [`.agents-project/受け入れ基準ルール.md`](../../.agents-project/受け入れ基準ルール.md)
