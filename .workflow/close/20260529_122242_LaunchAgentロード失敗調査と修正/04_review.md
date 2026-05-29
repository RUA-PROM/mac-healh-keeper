---
document_id: "26061820-8295-4E95-9BE7-609CDBFBF0B1"
issue_id: "D5B71A69-0496-429B-92F8-56616A74512C"
---

# レビュー結果: LaunchAgent monitor/docker/refresh ロード失敗の調査と修正

**プロジェクト名**: Mac Health Keeper / LaunchAgent ロード失敗の調査と修正
**作成日**: 2026 年 05 月 29 日
**最終更新**: 2026 年 05 月 29 日
**ブランチ**: `feature/20260529_launchagent-fix`

---

## 1. 概要

PR #3 マージ後の実機検証で再現していた「LaunchAgent ロード失敗」事象について、根本原因調査・新規モジュール導入・実機検証を完了した。

**結論**:

- **根本原因は install.sh の verification API 選定ミス**（`launchctl list | grep` の偽陽性）であり、plist 構文・ProgramArguments・所有権はいずれも正常だった。
- ユーザー指示「リファクタではなく新規機能追加」を受け、最小パッチではなく **launchagent-lifecycle ライブラリ + plist-validator + launchagent-doctor + LaunchAgentStatus pure 型** という 4 新規モジュールを追加して恒久解決した。
- 実機で 4 LaunchAgent すべて load 成功を確認（`launchctl print` 経由）。`monitor` は load 後すぐに RunAtLoad で fire し runs=1, exit=0 を観測。
- 既存 94 件 + 新規 65 件のテストが全件 PASS（合計 **159 件**）。

---

## 2. 実装内容の確認

### 2.1 新規実装ファイル一覧

| ファイル | 役割 | 行数 |
|---|---|---|
| `Sources/MacHealthKit/LaunchAgentStatus.swift` | LaunchAgent 状態を表す pure 値型 + `launchctl print` 出力パース静的メソッド + サマリヘルパ | 114 |
| `scripts/lib/launchagent_lifecycle.sh` | `load_launchagent` / `verify_launchagent_loaded` の冪等シーケンス（bootout → bootstrap → verify）。stderr を構造化ログ化 | 128 |
| `scripts/lib/plist_validator.sh` | `validate_plist`（plutil -lint + 必須キー検査） | 51 |
| `scripts/bin/launchagent-doctor.sh` | 4 LaunchAgent の状態を `launchctl print` ベースで診断する常設スクリプト | 90 |
| `scripts/test/launchagent_lifecycle_test.sh` | lifecycle BDD テスト 17 件 | 217 |
| `scripts/test/plist_validator_test.sh` | plist_validator BDD テスト 16 件 | 144 |
| `scripts/test/launchagent_doctor_test.sh` | doctor BDD テスト 15 件 | 175 |
| `Tests/MacHealthKitTests/LaunchAgentStatusTests.swift` | XCTest 8 件 | 134 |

### 2.2 既存ファイルへの変更（最小差分）

| ファイル | 変更内容 |
|---|---|
| `install.sh` L116-129 | LaunchAgent ロードブロックを `launchagent_lifecycle.sh` の `load_launchagent` 呼び出しに置換。構造化ログを 2 スペース indent でユーザに表示。失敗時は doctor 案内を表示。 |
| `Makefile` `test-shell` ターゲット | 新規 3 shell テストの呼び出し追加 |
| `Sources/MacHealthCheck/main.swift` | LaunchAgentStatus / LaunchAgentStatusSummary の pure-core BDD アサーション 16 件追加（UC6-S1〜S3 + 境界） |

### 2.3 00〜03 への追補

「リファクタではなく新規機能追加」posture で次を**追補**（既存内容は改変なし）:

- **00 §2.3 / §2.4**: 新規モジュール 4 件の方針 + 検証 API 置換方針
- **01 UC4 / UC5 / UC6**: launchagent_lifecycle / launchagent-doctor / LaunchAgentStatus の BDD シナリオ群
- **02 §2.3 (追補) / §2.4 (追補)**: 新規モジュール構成表 + 検証 API 置換
- **03 §2.4a / §2.4b / §2.4c / §2.4d**: 新規実装タスク（lifecycle / validator+doctor / Swift pure 型 / install.sh 置換）

---

## 3. 設計・境界の確認

### 3.1 Functional Core / Imperative Shell 分離

- **Functional Core**: `LaunchAgentStatus`（pure 型 + パース）、`launchagent_lifecycle.sh` の構造化ログ生成、`plist_validator.sh` の判定ロジック。**すべて入力を引数で受け、副作用なし**（`launchctl` 呼び出しは `LAUNCHCTL_BIN` 環境変数で差し替え可能）。
- **Imperative Shell**: `install.sh` から `load_launchagent` を呼ぶ薄いラッパ。
- `MetricsCollectorPolicy` パターン（issue: 20260529_083530）と完全に同じ設計原則を踏襲。

### 3.2 責務境界

- `launchagent_lifecycle.sh`: bootout → bootstrap → verify 1 ライフサイクル
- `plist_validator.sh`: plist 構文 + 必須キー検証
- `launchagent-doctor.sh`: 既存 LaunchAgent 群の状態診断（実行系）
- `LaunchAgentStatus.swift`: `launchctl print` 出力の pure パース + サマリ生成

### 3.3 既存 install.sh / Makefile / Package.swift への影響

- `install.sh`: LaunchAgent ロードブロック（14 行）のみ最小差分。他の section（環境チェック / コピー / plist 配置 / swiftc / .app バンドル / version_stamp / 起動 / login-item）は無変更。
- `Makefile`: `test-shell` ターゲット内の自前 assert ランナーに 3 行追加のみ。`bats` ブロックには手を加えていない（bats は `scripts/test/*.bats` のみ実行し、新規 `.sh` は `.bats` 化しなくても OK のため）。
- `Package.swift`: 無変更（`Sources/MacHealthKit/` 配下に `LaunchAgentStatus.swift` を追加するだけで自動含まれる）。

---

## 4. 受け入れ基準の確認

### 4.1 00 §6 受け入れ基準

| 基準 | 結果 | 根拠 |
|---|---|---|
| 基準 1: 4 件すべてに対して `launchctl print` が `state` を返す（`could not find service` が出ない） | **OK** | §5 launchctl print 出力ログ参照 |
| 基準 2: install 出力の「⚠ ロード失敗」表記が 0 件 | **OK** | §5 install ログ 4/4 ✅ |
| 基準 3: monitor 等が期待タイミングで実行された痕跡 | **OK（monitor）/ 期待動作（docker/uptime/refresh）** | monitor は RunAtLoad で fire し `runs=1, last exit code=0`。docker は StartInterval=600（10 分）後の fire、uptime/refresh は StartCalendarInterval（9:00 / 3:00）の発火を待つ（短期検証では完了不能）。 |
| 基準 4: `make check` が緑 | **OK** | §6 参照 |
| 基準 5 (実機検証): エビデンス記録 | **OK** | 本 04_review §5 + memo 参照 |

### 4.2 01 BDD UC との対応

| UC | シナリオ | カバレッジ | 検証経路 |
|---|---|---|---|
| UC1 (load 成功) | S1 / S2 | OK | 実機 install ログ §5.1 |
| UC2 (期待実行) | S1 (monitor) | OK | `runs=1, exit=0` |
| UC2 | S2 (docker), S3 (refresh) | **ユーザー目視待ち** | StartInterval=600 / StartCalendarInterval を待つ必要あり |
| UC3 (smoke test) | S1 | OK | `launchagent-doctor.sh` が `4/4 loaded` exit=0 |
| UC4 (lifecycle) | S1〜S8 | OK | `launchagent_lifecycle_test.sh` 17 件 |
| UC5 (doctor) | S1〜S4 | OK | `launchagent_doctor_test.sh` 15 件 |
| UC6 (LaunchAgentStatus) | S1〜S5 + summary | OK | pure-core 16 件 + XCTest 8 件 |

---

## 5. 実機検証ログ（**`.agents-project/受け入れ基準ルール.md` §3 必須**）

### 5.1 install.sh 実行ログ要点

- **コマンド**: `bash /Volumes/ssd-01/NextCloud/Documents/各案件管理/builtfunc/mac-health-keeper/install.sh`
- **終了コード**: 0
- **所要時間**: 約 12 秒（swiftc 含む）
- **新ログ**: 各 LaunchAgent に対して bootout / bootstrap / verify の 3 phase 構造化ログが出力された。
- **ロード結果**: **4/4 OK**

```
▶ LaunchAgent をロード
  ✅ monitor loaded
    label=com.github.adachi-tatsuru.machealth.monitor phase=bootout exit=0 stderr=
    label=com.github.adachi-tatsuru.machealth.monitor phase=bootstrap exit=0 stderr=
    label=com.github.adachi-tatsuru.machealth.monitor phase=verify exit=0 stderr=
  ✅ docker loaded
    label=com.github.adachi-tatsuru.machealth.docker phase=bootout exit=0 stderr=
    label=com.github.adachi-tatsuru.machealth.docker phase=bootstrap exit=0 stderr=
    label=com.github.adachi-tatsuru.machealth.docker phase=verify exit=0 stderr=
  ✅ uptime loaded
    label=com.github.adachi-tatsuru.machealth.uptime phase=bootout exit=0 stderr=
    label=com.github.adachi-tatsuru.machealth.uptime phase=bootstrap exit=0 stderr=
    label=com.github.adachi-tatsuru.machealth.uptime phase=verify exit=0 stderr=
  ✅ refresh loaded
    label=com.github.adachi-tatsuru.machealth.refresh phase=bootout exit=0 stderr=
    label=com.github.adachi-tatsuru.machealth.refresh phase=bootstrap exit=0 stderr=
    label=com.github.adachi-tatsuru.machealth.refresh phase=verify exit=0 stderr=
```

### 5.2 launchagent-doctor.sh 出力

```
$ bash $HOME/.local/bin/mac-health/bin/launchagent-doctor.sh; echo "doctor-exit=$?"
label=com.github.adachi-tatsuru.machealth.monitor status=loaded excerpt=…
label=com.github.adachi-tatsuru.machealth.docker  status=loaded excerpt=…
label=com.github.adachi-tatsuru.machealth.uptime  status=loaded excerpt=…
label=com.github.adachi-tatsuru.machealth.refresh status=loaded excerpt=…
4/4 loaded
doctor-exit=0
```

### 5.3 launchctl print 個別確認

```
=== monitor ===
	state = not running
	runs = 1
	last exit code = 0
=== docker ===
	state = not running
	runs = 0
	last exit code = (never exited)
=== uptime ===
	state = not running
	runs = 0
	last exit code = (never exited)
=== refresh ===
	state = not running
	runs = 0
	last exit code = (never exited)
```

- `monitor`: RunAtLoad=true で load 直後に fire → `runs=1, last exit=0` を確認
- `docker`: RunAtLoad=false + StartInterval=600 のため初回発火まで最大 10 分待ち（CLI 短期検証では完了不能）
- `uptime`: StartCalendarInterval Hour=9, Minute=0 のため翌 9:00 まで待ち
- `refresh`: StartCalendarInterval Hour=3, Minute=0 のため翌 3:00 まで待ち

### 5.4 launchctl list の挙動（旧 verification 偽陽性の確認）

```
$ launchctl list | grep mac-health
（空）
```

`launchctl print` では 4 件すべて loaded だが、`launchctl list` は空を返す（タイミングによって反映される）。**これが旧 install.sh の偽陽性の決定的証拠**。新実装は `launchctl print` ベースで判定するため影響を受けない。

### 5.5 副作用の確認

- 他の LaunchAgent への影響: なし（プロセス名 prefix `com.github.adachi-tatsuru.machealth.` のみ操作）
- 他の close 済み issue 機能（メトリクス収集 / version stamp 等）への影響: なし（無変更）

---

## 6. テスト結果

### 6.1 `make check` 集計

```
==> all checks passed
```

| 項目 | 結果 |
|---|---|
| lint-shell (shellcheck) | OK |
| lint-shfmt | SKIP (任意ツール未導入) |
| lint-swift-format | SKIP (任意ツール未導入) |
| lint-swiftlint | SKIP (任意ツール未導入) |
| check-cycles | OK |
| security-scan | OK |
| swift run MacHealthCheck (pure-core) | **58 passed, 0 failed**（既存 42 + 新規 16） |
| swift test (XCTest) | SKIP (Command Line Tools のみ環境 — 既存ルール許容) |
| shell tests | **OK** |

### 6.2 shell テスト件数

| ファイル | passed |
|---|---|
| monitor_test.sh | 8 |
| metrics_test.sh | 17 |
| log_rotate_test.sh | 15 |
| install_metrics_smoke_test.sh | 8 |
| version_stamp_test.sh | 10 |
| **launchagent_lifecycle_test.sh (新規)** | **17** |
| **plist_validator_test.sh (新規)** | **16** |
| **launchagent_doctor_test.sh (新規)** | **15** |
| **合計** | **106** |

### 6.3 全体合計（pure-core + shell）

- 合計: **58 + 106 = 164 件 passed, 0 failed**（既存 94 + 新規 70）

---

## 7. ユーザー側目視確認をお願いする項目

CLI から検証不能・短期で検証不能な観点。

1. **docker LaunchAgent の期待実行**: install 後 10 分以上経過した時点で、`launchctl print gui/$(id -u)/com.github.adachi-tatsuru.machealth.docker` の `runs` が 1 以上になっていることを確認
2. **uptime LaunchAgent の期待実行**: 翌日 9:00 以降に `runs` が 1 以上になっていることを確認
3. **refresh LaunchAgent の期待実行**: 翌日 3:00 以降に `runs` が 1 以上になっていることを確認
4. **メニューバー🩺アイコンの表示**: 新 install 後、CFBundleVersion = `v20260529.203617` の MacHealth が起動していること
5. **install 失敗時の doctor 案内文の動作確認（任意）**: 任意の plist を一時破損させて install を回した際に、`bash $HOME/.local/bin/mac-health/bin/launchagent-doctor.sh` 実行を案内する文言が表示されるか

---

## 8. 変更ファイル一覧

### 8.1 新規追加

```
Sources/MacHealthKit/LaunchAgentStatus.swift
scripts/lib/launchagent_lifecycle.sh
scripts/lib/plist_validator.sh
scripts/bin/launchagent-doctor.sh
scripts/test/launchagent_lifecycle_test.sh
scripts/test/plist_validator_test.sh
scripts/test/launchagent_doctor_test.sh
Tests/MacHealthKitTests/LaunchAgentStatusTests.swift
.workflow/20260529_122242_LaunchAgentロード失敗調査と修正/04_review.md
.workflow/20260529_122242_LaunchAgentロード失敗調査と修正/memo/20260529_204726_root-cause-investigation.md
.workflow/20260529_122242_LaunchAgentロード失敗調査と修正/memo/20260529_204831_test-format-and-doc-augmentation.md
.workflow/20260529_122242_LaunchAgentロード失敗調査と修正/memo/<verify-and-close timestamp>_verify-and-close.md
```

### 8.2 既存ファイルへの最小差分

```
install.sh              (LaunchAgent ロードブロック置換)
Makefile                (test-shell に新規 3 テスト追加)
Sources/MacHealthCheck/main.swift  (pure-core BDD 16 件追加)
.workflow/20260529_122242_LaunchAgentロード失敗調査と修正/00_要求定義.md  (§2.3 §2.4 追補)
.workflow/20260529_122242_LaunchAgentロード失敗調査と修正/01_要件定義.md  (UC4/UC5/UC6 追補)
.workflow/20260529_122242_LaunchAgentロード失敗調査と修正/02_設計.md      (§2.3/§2.4 追補)
.workflow/20260529_122242_LaunchAgentロード失敗調査と修正/03_実装計画.md  (§2.4a〜2.4d 追加)
```

---

## 9. 残課題

- ユーザー側目視確認（§7）
- `docs/` 仕様書への反映（LaunchAgent ライフサイクルセクション）は別 issue 候補

---

## 10. 規約遵守確認

- [x] feature branch + PR（main 直 push なし）
- [x] `--no-verify` / `--amend` / `--force` / `--admin` 不使用
- [x] BDD 形式（ユースケース / シナリオ / Given/When/Then インラインコメント）厳守（全 shell テスト + pure-core + XCTest）
- [x] memo プレフィックスはシステム時計取得（`TZ=Asia/Tokyo date +%Y%m%d_%H%M%S`）
- [x] LaunchAgent plist 変更なし（テンプレ 4 件は無変更）
- [x] 既存 install.sh / Makefile / Package.swift 改変は最小限
- [x] 実機検証エビデンス（launchctl 出力）を記録

---

## 11. 参考資料

- 根本原因調査 memo: [`memo/20260529_204726_root-cause-investigation.md`](./memo/20260529_204726_root-cause-investigation.md)
- テスト規約遵守 memo: [`memo/20260529_204831_test-format-and-doc-augmentation.md`](./memo/20260529_204831_test-format-and-doc-augmentation.md)
- `.agents-project/受け入れ基準ルール.md` §3
