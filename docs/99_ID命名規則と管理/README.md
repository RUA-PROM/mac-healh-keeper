---
document_id: "498FC4EC-EDE1-407E-A9D0-9B50C6BE0355"
---

このドキュメントは、Mac Health Keeper のドキュメントとコードで使用する **ID・命名規則** の一元管理を定義します。
システム仕様書作成ルールは [`.agents/DOCS_RULES.md`](../../.agents/DOCS_RULES.md) を参照してください。

# 99. ID 命名規則と管理

本ドキュメントは ID の **一元管理表** として機能します。新しい ID を追加・変更する際は本表を必ず更新し、各ドキュメントとの整合を保ってください。

---

## 99.1. ID プレフィックス一覧

| プレフィックス | 意味 | 使用箇所 |
| -------------- | ---- | -------- |
| `G` | GUI（画面） | [02 画面設計](../02_画面設計/README.md) |
| `F` | Functional Flow（機能フロー / 機能 ID） | [04 機能設計](../04_機能設計/README.md) |
| `S` | Sequence Diagram | [04 機能設計](../04_機能設計/README.md)（`F<feature>-S<n>` の形でも併用） |
| `T` | Table / 値型・ファイル形式・スキーマ | [03 データ設計](../03_データ設計/README.md) |

> **本プロジェクトは外部 API を持たない** ため、テンプレートにある `API` プレフィックスは使用しません。

---

## 99.2. 画面 ID（G001-GXXX）

| ID | 画面名 | 説明 | 参照 |
| -- | ------ | ---- | ---- |
| G001 | メニューバードロップダウン | クリックで展開する NSMenu 全体 | [02 画面設計 §2.1 / §2.3](../02_画面設計/README.md#21-画面構成図メニュー全体) |
| G002 | メトリクス（6 行 + 最終更新） | 稼働時間・負荷・メモリ・スワップ・Docker + 最終更新 (⌘R) | [02 画面設計 §2.3 G002](../02_画面設計/README.md#g002-メトリクスdisabled-表示行--最終更新行) |
| G003 | クイック対処 | App Refresh / sudo purge / memory_pressure / Docker Quit | [02 画面設計 §2.3 G003](../02_画面設計/README.md#g003-クイック対処4-項目) |
| G004 | ジョブ一覧 | 4 ジョブの ON/OFF 行（🟢/⚪） | [02 画面設計 §2.3 G004](../02_画面設計/README.md#g004-ジョブ一覧4-行クリックで-onoff) |
| G005 | 今すぐ実行 | 4 ジョブの即実行行（▶） | [02 画面設計 §2.3 G005](../02_画面設計/README.md#g005-今すぐ実行4-項目) |
| G006 | ログ・通知テスト | 通知履歴 ⌘E / 監視ログ ⌘M / 通知テスト ⌘T | [02 画面設計 §2.3 G006](../02_画面設計/README.md#g006-ログ通知テスト3-項目) |
| G007 | 全停止／全再開 | 全ジョブ pause/resume | [02 画面設計 §2.3 G007](../02_画面設計/README.md#g007-全停止全再開2-項目) |
| G008 | フッター | ヘルプ・About・終了 (⌘Q) | [02 画面設計 §2.3 G008](../02_画面設計/README.md#g008-フッターヘルプabout終了) |
| G009 | ジョブ起動／停止失敗アラート | `toggleJob` 後の実態不一致時 | [02 画面設計 §2.4 G009](../02_画面設計/README.md#g009-ジョブ起動停止失敗アラート) |
| G010 | sudo purge 確認アラート | 実行前確認 | [02 画面設計 §2.4 G010](../02_画面設計/README.md#g010-sudo-purge-確認アラート) |
| G011 | 各指標の意味ヘルプアラート | `showMetricsHelp` の本文 | [02 画面設計 §2.4 G011](../02_画面設計/README.md#g011-各指標の意味ヘルプアラート) |
| G012 | About アラート | バージョン情報 | [02 画面設計 §2.4 G012](../02_画面設計/README.md#g012-about-アラート) |

---

## 99.3. 機能 ID（F001-FXXX）

| ID | 機能名 | 説明 | 参照 |
| -- | ------ | ---- | ---- |
| F001 | メニューバー表示 | アイコン・NSMenu 構築・再描画 | [04 機能設計 / メニューバー表示](../04_機能設計/メニューバー表示/README.md) |
| F002 | メトリクス収集 | `metrics.sh` 呼出 + `MetricsParser` | [04 機能設計 / メトリクス収集](../04_機能設計/メトリクス収集/README.md) |
| F003 | ジョブ ON/OFF（CQRS） | `JobController` の Command / Query 分離 | [04 機能設計 / ジョブON_OFF](../04_機能設計/ジョブON_OFF/README.md) |
| F004 | クイック対処 | 4 種のワンクリック対処 | [04 機能設計 / クイック対処](../04_機能設計/クイック対処/README.md) |
| F005 | 監視ジョブ（4 種） | monitor / docker / uptime / refresh | [04 機能設計 / 監視ジョブ](../04_機能設計/監視ジョブ/README.md) |
| F006 | 通知（注入耐性付き） | argv 渡し + cooldown | [04 機能設計 / 通知](../04_機能設計/通知/README.md) |
| F007 | ログ・ローテーション | `log.sh` + `lock.sh` | [04 機能設計 / ログとローテーション](../04_機能設計/ログとローテーション/README.md) |
| F008 | LaunchAgent 配備 | `install.sh` / `uninstall.sh` | [04 機能設計 / LaunchAgent配備](../04_機能設計/LaunchAgent配備/README.md) |

---

## 99.4. シーケンス図 ID（S001-SXXX）

シーケンス図は機能 ID と複合して `F<n>-S<n>` で参照します。

| ID | 図名 | 参照 |
| -- | ---- | ---- |
| F001-S1 | メニュー構築シーケンス | [04 機能設計 / メニューバー表示](../04_機能設計/メニューバー表示/README.md#処理フローf001-s1-メニュー構築シーケンス) |
| F002-S1 | `collect()` の主シーケンス | [04 機能設計 / メトリクス収集](../04_機能設計/メトリクス収集/README.md#処理フローf002-s1-collect-の主シーケンス) |
| F003-S1 | 個別 toggle | [04 機能設計 / ジョブON_OFF](../04_機能設計/ジョブON_OFF/README.md#f003-s1-個別-toggleメニューの--クリック) |
| F003-S2 | isLoaded（Query） | [04 機能設計 / ジョブON_OFF](../04_機能設計/ジョブON_OFF/README.md#f003-s2-isloadedquery副作用なし) |
| F003-S3 | 全停止／全再開 | [04 機能設計 / ジョブON_OFF](../04_機能設計/ジョブON_OFF/README.md#f003-s3-全停止全再開) |
| F004-S1 | quickPurge の確認 → 実行 | [04 機能設計 / クイック対処](../04_機能設計/クイック対処/README.md#処理フローf004-s1-quickpurge-の確認--実行) |
| F004-S2 | quickAppRefresh | [04 機能設計 / クイック対処](../04_機能設計/クイック対処/README.md#処理フローf004-s2-quickapprefresh) |
| F006-S1 | Swift 側通知（argv 渡し） | [04 機能設計 / 通知](../04_機能設計/通知/README.md#f006-s1-swift-側通知argv-渡し注入耐性) |
| F006-S2 | シェル側通知（cooldown 経由） | [04 機能設計 / 通知](../04_機能設計/通知/README.md#f006-s2-シェル側通知cooldown-経由案-b-相当) |
| F007-S1 | ジョブの終了処理シーケンス | [04 機能設計 / ログとローテーション](../04_機能設計/ログとローテーション/README.md#f007-s1-ジョブの終了処理シーケンス) |
| F007-S2 | cooldown 更新 | [04 機能設計 / ログとローテーション](../04_機能設計/ログとローテーション/README.md#f007-s2-cooldown-更新read-modify-write) |
| F008-S1 | install.sh フロー | [04 機能設計 / LaunchAgent配備](../04_機能設計/LaunchAgent配備/README.md#installsh-の処理フロー) |
| F008-S2 | uninstall.sh フロー | [04 機能設計 / LaunchAgent配備](../04_機能設計/LaunchAgent配備/README.md#uninstallsh-の処理フロー) |

---

## 99.5. テーブル／データ ID（T01-TXX）

リレーショナル DB は持ちませんが、データ設計の各エンティティに T プレフィックスを付与します。

| ID | データ名 | 種別 | 参照 |
| -- | -------- | ---- | ---- |
| T01 | `MetricsSnapshot` | Swift 値型 | [03 データ設計 §3.2.1](../03_データ設計/README.md#321-t01-metricssnapshotmetricsswift) |
| T02 | `JobStatus` | Swift 値型 | [03 データ設計 §3.2.2](../03_データ設計/README.md#322-t02-jobstatusmetricsswift) |
| T03 | `ScheduleKind` | Swift enum | [03 データ設計 §3.2.3](../03_データ設計/README.md#323-t03-schedulekindjobcatalogswift) |
| T04 | `MenuItemSpec` / `MenuAction` | Swift 値型 / enum | [03 データ設計 §3.2.4](../03_データ設計/README.md#324-t04-menuitemspec--menuactionmenumodelswift) |
| T05 | `JobCatalog` | Swift 値型 | [03 データ設計 §3.2.5](../03_データ設計/README.md#325-t05-jobcatalogjobcatalogswift) |
| T06 | `events.log` | テキストログ（通知履歴） | [03 データ設計 §3.3.1](../03_データ設計/README.md#331-t06-eventslog通知履歴) |
| T07 | `<job>.log` | テキストログ（各ジョブ） | [03 データ設計 §3.3.2](../03_データ設計/README.md#332-t07-jobログ各ジョブの実行ログ) |
| T08 | `<job>.log.<N>` | ローテート世代ファイル | [03 データ設計 §3.3.3](../03_データ設計/README.md#333-t08-joblognローテート世代ファイル) |
| T09 | `launchd.<job>.out` / `.err` | launchd 標準出力／エラー | [03 データ設計 §3.3.4](../03_データ設計/README.md#334-t09-launchdjobout--launchdjoberr) |
| T10 | `rotate.err` | ローテート失敗専用ログ | [03 データ設計 §3.3.5](../03_データ設計/README.md#335-t10-rotateerrローテート失敗の専用ログ) |
| T11 | `COOLDOWN_FILE`（key:epoch） | テキスト状態ファイル | [03 データ設計 §3.3.6](../03_データ設計/README.md#336-t11-cooldown_file通知クールダウン) |
| T12 | `.docker-state` | テキスト状態ファイル | [03 データ設計 §3.3.7](../03_データ設計/README.md#337-t12-docker-statedocker-アイドル開始時刻) |
| T13 | `$LOG_DIR/.locks/<name>.lock` | mkdir ロックディレクトリ | [03 データ設計 §3.3.8](../03_データ設計/README.md#338-t13-ロックファイル) |

---

## 99.6. コード内の命名規則（実装）

`.agents/spec/03_命名規則.md` に従う。**禁止命名**: `helpers` / `misc` / `common` / `utils`（責務単位で命名すること）。

### 99.6.1. launchd ラベル

`com.github.adachi-tatsuru.machealth.<job>` の形式（`<job>` = `monitor` / `docker` / `uptime` / `refresh`）。

| ラベル | スクリプト | 生成 |
| ------ | ---------- | ---- |
| `com.github.adachi-tatsuru.machealth.monitor` | `monitor.sh` | `JobCatalog.label(for: "monitor")` |
| `com.github.adachi-tatsuru.machealth.docker` | `check-docker.sh` | `JobCatalog.label(for: "docker")` |
| `com.github.adachi-tatsuru.machealth.uptime` | `check-uptime.sh` | `JobCatalog.label(for: "uptime")` |
| `com.github.adachi-tatsuru.machealth.refresh` | `refresh.sh` | `JobCatalog.label(for: "refresh")` |
| `com.github.adachi-tatsuru.machealth.app` | アプリ本体（CFBundleIdentifier） | `src/Info.plist` |

### 99.6.2. cooldown キー

`$COOLDOWN_FILE` の各行は `<key>:<epoch>`。key の一覧:

| key | 用途 | 設定箇所 |
| --- | ---- | -------- |
| `swap` | スワップ蓄積 | `monitor.sh::should_notify "swap"` |
| `compressed` | 圧縮メモリ | `monitor.sh::should_notify "compressed"` |
| `load` | 高負荷 | `monitor.sh::should_notify "load"` |
| `pressure` | メモリ圧迫 critical | `monitor.sh::should_notify "pressure"` |
| `test` | 通知テスト（`mac-health test`） | `scripts/bin/mac-health::test` |

### 99.6.3. メトリクス関数命名

| プレフィックス | 用途 | 例 |
| -------------- | ---- | -- |
| `metrics_parse_*` | 純粋パース関数（外部コマンド非依存） | `metrics_parse_swap_mb` / `metrics_parse_compressed_gb` / `metrics_parse_load_1m` / `metrics_parse_free_pct` |
| `metrics_*` （`_raw`/`_mb`/`_gb` 等接尾） | 取得ラッパ（実コマンド実行） | `metrics_swap_used_mb` / `metrics_compressed_gb` / `metrics_load_1m` / `metrics_memory_free_pct` / `metrics_uptime_days_now` / `metrics_uptime_hours_now` / `metrics_docker_status` |

### 99.6.4. ロックファイル命名

`$LOG_DIR/.locks/<name>.lock`。`<name>`:

| name | 用途 |
| ---- | ---- |
| `rotate` | `rotate_file` の世代シフト直列化 |
| `notify-cooldown` | `should_notify` の read-modify-write 直列化 |

### 99.6.5. 設定変数（`thresholds.sh`）命名

| プレフィックス | 例 |
| -------------- | -- |
| `THRESHOLD_*` | `THRESHOLD_SWAP_USED_MB` / `THRESHOLD_COMPRESSED_GB` / `THRESHOLD_LOAD_AVG_MULTIPLIER` |
| `DOCKER_*` | `DOCKER_IDLE_GRACE_MINUTES` |
| `UPTIME_*` | `UPTIME_WARN_DAYS` |
| `NOTIFICATION_*` | `NOTIFICATION_COOLDOWN_MIN` |
| `MHK_*`（log.sh / lock.sh 用） | `MHK_ROTATE_MAX_BYTES` / `MHK_ROTATE_KEEP_GENERATIONS` / `MHK_ROTATE_EXTS` / `MHK_LOCK_TIMEOUT_SEC` |

---

## 99.7. ドキュメント命名規則

### 99.7.1. document_id（UUID）

各ドキュメントの frontmatter に **UUID 8-4-4-4-12 形式** で付与する（重複禁止）。新規発行は `uuidgen` を使用。既存は不変。

### 99.7.2. issue_id

`.workflow/<timestamp>_<title>/` に作成する 00〜04 ドキュメント群の `frontmatter.issue_id`（UUID）。サブ issue は `90_issues/<sub>/` 配下に同形式で持つ。

### 99.7.3. メモプレフィックス

ワークフローメモは `YYYYMMDD_HHMMSS_<title>` の形式（JST、`.agents/scripts/memo-prefix.sh` 参照）。本 docs のレビュー記録（`docs/00_review/`）も同形式。

### 99.7.4. テストファイル命名

| 種別 | 命名 | 例 |
| ---- | ---- | -- |
| XCTest（Swift） | `<対象>Tests.swift` | `MenuModelTests.swift` / `JobControllerTests.swift` |
| bats（シェル） | `<対象>.bats` | `monitor.bats` / `metrics.bats` / `log_rotate.bats` |
| 自前ランナー（シェル） | `<対象>_test.sh` | `monitor_test.sh` / `metrics_test.sh` / `log_rotate_test.sh` |

> シェル関数命名で **`helpers` / `misc` / `common` / `utils` は禁止**（`.agents/spec/03_命名規則.md`）。代わりに責務単位（`log` / `notify` / `metrics` / `lock`）を使う。

---

## 99.8. ID 管理のルール

1. 新規 ID 追加時は本表を必ず更新する。
2. ID 定義時は本表を参照し重複・不整合がないことを確認する。
3. ID 変更時は本表 + 該当する全ドキュメントを同時更新する。
4. ID 削除は慎重に行う（過去のドキュメントとの整合性のため、原則として残す）。

---

## 参考資料

- [01 システム概要](../01_システム概要/README.md)
- [02 画面設計](../02_画面設計/README.md)
- [03 データ設計](../03_データ設計/README.md)
- [04 機能設計](../04_機能設計/README.md)
- `.agents/spec/03_命名規則.md`・`.agents/spec/02_ディレクトリ構造方針.md`

---

**最終更新**: 2026 年 05 月 28 日 / **maintainer**: docs worker
