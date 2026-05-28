---
document_id: "FA5889B1-E719-4781-AD95-61CE8C765EC4"
---

このドキュメントは、Mac Health Keeper のソースツリーと各ディレクトリの役割を定義します。
システム仕様書作成ルールは [`.agents/DOCS_RULES.md`](../../../.agents/DOCS_RULES.md) を参照してください。

> 本ドキュメントは「生きているドキュメント」です。実装変更時（各サブ issue 完了時）に更新し、レビュー結果は [`docs/00_review/`](../../00_review/) に記録します。

# 4. ディレクトリ構成

リポジトリのソースツリーと各ディレクトリの役割を、`.agents/spec/02_ディレクトリ構造方針.md` の「**責務単位**でディレクトリを切る」考え方と対応づけて示します。パスはすべてリポジトリルートからの相対表記です（個人の絶対パスは記載しません）。生成物（`.build` / `.DS_Store` 等）は一覧から除外します。

---

## 4.1. トップレベル構成

### ツリー

```text
mac-health-keeper/
├── src/                       # UI 層（AppKit 依存）
│   ├── MacHealth.swift        #   AppDelegate（調整役）
│   ├── MenuBuilder.swift      #   NSMenu 変換
│   ├── MetricsCollector.swift #   メトリクス収集（Imperative Shell）
│   └── Info.plist             #   アプリの Info.plist
├── Sources/
│   └── MacHealthKit/          # Domain(Functional Core) + Infra(Imperative Shell)・Foundation のみ
│       ├── JobCatalog.swift
│       ├── ScheduleTiming.swift
│       ├── MetricsParser.swift
│       ├── MenuModel.swift
│       ├── Metrics.swift
│       ├── AppleScriptEscaper.swift
│       ├── ShellRunner.swift
│       └── JobController.swift
├── Tests/
│   └── MacHealthKitTests/     # XCTest 単体テスト
├── scripts/
│   ├── bin/                   # 実行スクリプト・CLI（launchd 起動対象）
│   ├── lib/                   # 共通ユーティリティ（log/notify/metrics/lock）
│   ├── config/                # 編集可能な設定値（thresholds.sh）
│   └── test/                  # シェルのテスト（bats / *_test.sh）
├── launchagents/              # launchd ジョブ定義テンプレート（*.plist.template）
├── docs/                      # システム仕様書（本ドキュメント群）
├── .agents/                   # 実行契約・規約（汎用テンプレート）
├── .agents-project/           # プロジェクト固有ルール（.agents より優先）
├── .workflow/                 # ワークフロー成果物（00〜04・issue・workflow.db）
├── Package.swift              # SwiftPM 構成
├── Makefile                   # ビルド・テスト
├── install.sh / uninstall.sh  # 配布 / 撤去
├── README.md / LICENSE        # プロジェクト README・ライセンス
└── AGENTS.md / CLAUDE.md      # エージェント向け規約の入口
```

### トップレベル役割表（責務単位・spec/02 対応）

| パス | 役割（責務単位） |
| ---- | ---------------- |
| `src/` | UI 層（AppKit 依存）。`AppDelegate`（`MacHealth.swift`）・`MenuBuilder`・`MetricsCollector`・`Info.plist`。 |
| `Sources/MacHealthKit/` | Domain（Functional Core）＋ Infra（Imperative Shell）。Foundation のみ依存。テスト対象。 |
| `Tests/MacHealthKitTests/` | XCTest 単体テスト（Core / Infra の純粋・契約テスト）。 |
| `scripts/bin/` | 実行スクリプト（monitor / docker / uptime / refresh）と CLI `mac-health`。launchd 起動対象。 |
| `scripts/lib/` | 共通ユーティリティ（log・notify・metrics・lock）。Functional Core / Imperative Shell。 |
| `scripts/config/` | 編集可能な設定値（`thresholds.sh`）。 |
| `scripts/test/` | シェルのテスト（bats / `*_test.sh`）。 |
| `launchagents/` | launchd ジョブ定義テンプレート（`*.plist.template`）。 |
| `docs/` | システム仕様書（本 issue の成果物）。 |
| `.agents/` | 実行契約・規約（汎用テンプレート）。 |
| `.agents-project/` | プロジェクト固有ルール（`.agents` より優先）。 |
| `.workflow/` | ワークフロー成果物（00〜04・issue・workflow.db）。 |
| ルート（`Package.swift` / `Makefile` / `install.sh` / `uninstall.sh`） | SwiftPM 構成・ビルド・配布 / 撤去。 |

---

## 4.2. Swift（`src` / `Sources/MacHealthKit` / `Tests`）

| パス | 役割 |
| ---- | ---- |
| `src/MacHealth.swift` | `AppDelegate`。メニューバー UI とユーザー操作の調整役。各層へ委譲する。 |
| `src/MenuBuilder.swift` | `[MenuItemSpec]` を NSMenu / NSMenuItem へ変換する薄い AppKit 部。 |
| `src/MetricsCollector.swift` | 実コマンドを実行し MetricsParser に委譲して MetricsSnapshot を組み立てる（Imperative Shell）。 |
| `src/Info.plist` | アプリの Info.plist（メニューバー常駐アプリ設定）。 |
| `Sources/MacHealthKit/*` | Domain（`JobCatalog`・`ScheduleTiming`・`MetricsParser`・`MenuModel`・`Metrics`・`AppleScriptEscaper`）と Infra（`ShellRunner`・`JobController`）。AppKit 非依存ゆえテスト可能。 |
| `Tests/MacHealthKitTests/*` | MacHealthKit の XCTest 単体テスト（JobCatalog / ScheduleTiming / MetricsParser / MenuModel / JobController / ShellRunner 契約・注入 / AppleScriptEscaper 等）。 |

> **境界の根拠**: UI（AppKit 依存）を `src/`、テスト可能な純粋ロジック＋副作用境界（Foundation のみ）を `Sources/MacHealthKit/` に分離することで、Domain / Infra を AppKit から独立して検証できます（責務単位の分離）。

---

## 4.3. シェル（`scripts/{bin,lib,config,test}`）

| パス | 役割 |
| ---- | ---- |
| `scripts/bin/monitor.sh` | メモリ／負荷監視ジョブ（launchd: monitor）。 |
| `scripts/bin/check-docker.sh` | Docker アイドル監視ジョブ（launchd: docker）。 |
| `scripts/bin/check-uptime.sh` | 長期稼働の通知ジョブ（launchd: uptime）。 |
| `scripts/bin/refresh.sh` | アプリ自動再起動ジョブ（launchd: refresh）。 |
| `scripts/bin/mac-health` | CLI エントリポイント（`run <job>` 等）。 |
| `scripts/bin/notification_cooldown.sh` | 通知クールダウン制御。 |
| `scripts/lib/log.sh` | ログ記録・世代ローテート（`rotate_logs`）。 |
| `scripts/lib/notify.sh` | osascript によるデスクトップ通知。 |
| `scripts/lib/metrics.sh` | メトリクス取得処理の集約。 |
| `scripts/lib/lock.sh` | ローテート等の排他制御（多重実行の競合防止）。 |
| `scripts/config/thresholds.sh` | 閾値・ローテート世代数・クールダウン等の編集可能な設定値。 |
| `scripts/test/*` | シェルのテスト（`*.bats` / `*_test.sh`）。`make test-shell` で実行。 |

---

## 4.4. 配置物・運用（`launchagents` / ルートスクリプト）

| パス | 役割 |
| ---- | ---- |
| `launchagents/com.github.adachi-tatsuru.machealth.<job>.plist.template` | 各ジョブの launchd 定義テンプレート（`{{HOME}}` プレースホルダ）。`<job>` は monitor / docker / uptime / refresh。 |
| `install.sh` | スクリプト・LaunchAgents の配置と登録（`{{HOME}}` を実環境に展開）。 |
| `uninstall.sh` | 配置物の撤去・LaunchAgents の解除。 |
| `Makefile` | ビルド・テスト（Swift / シェル）のエントリポイント。 |
| `Package.swift` | SwiftPM のパッケージ定義（MacHealthKit ターゲット・テストターゲット）。 |

---

## 4.5. ドキュメント・規約（`docs` / `.agents` / `.agents-project` / `.workflow`）

| パス | 役割 |
| ---- | ---- |
| `docs/` | システム仕様書。`00_review/`（レビュー記録）・`01_システム概要/`（概要・アーキテクチャ・ディレクトリ構成）。 |
| `.agents/` | 実行契約・規約・spec・commands・skills（汎用）。 |
| `.agents-project/` | プロジェクト固有ルール（`.agents` より優先）。 |
| `.workflow/` | ワークフロー成果物（issue・00〜04・templates・workflow.db）。 |

---

## 4.6. テストディレクトリのルール（方針）

- **テストピラミッド**: 純粋ロジック（Domain）の単体テストを厚く配置する。
- **配置の一意性**: Swift（MacHealthKit）のテストは `Tests/MacHealthKitTests/`（XCTest）、シェルのテストは `scripts/test/`（bats / `*_test.sh`）に置き、例外を作らない。
- **命名**: Swift は `<対象>Tests.swift`、シェルは `<対象>_test.sh` / `<対象>.bats` で対象が分かるようにする。

---

## 4.7. 詳細ツリー（実物）

実リポジトリの構成を、生成物（`.build` / `.DS_Store` 等）を除いて示します。`{}` は同名拡張の集合表記です。

```text
mac-health-keeper/
├── src/                                                # UI 層（AppKit 依存）
│   ├── MacHealth.swift                                 #   AppDelegate（調整役）・@main
│   ├── MenuBuilder.swift                               #   [MenuItemSpec] → NSMenu 変換 + Selector マップ
│   ├── MetricsCollector.swift                          #   実コマンド実行 → MetricsParser 委譲（Imperative Shell）
│   └── Info.plist                                      #   LSUIElement=true / LSMinimumSystemVersion=11.0
├── Sources/
│   └── MacHealthKit/                                   # Domain(Functional Core) + Infra(Imperative Shell)
│       ├── JobCatalog.swift                            #   ジョブ ID/短名/頻度/ScheduleKind/label 規則
│       ├── ScheduleTiming.swift                        #   時刻計算（now 引数化・純粋）+ Calendar.utc ヘルパ
│       ├── MetricsParser.swift                         #   出力文字列 → メトリクス値の純粋パース
│       ├── MenuModel.swift                             #   Snapshot/Status/Catalog → [MenuItemSpec] 純粋生成
│       ├── Metrics.swift                               #   MetricsSnapshot / JobStatus（純粋値型）
│       ├── AppleScriptEscaper.swift                    #   osascript argv 渡し（案A）+ 文字列エスケープ（案B）
│       ├── ShellRunner.swift                           #   protocol ShellRunner + ZshShellRunner（引数配列・Process）
│       └── JobController.swift                         #   CQRS: isLoaded(query) / load/unload/toggle/enableAll/disableAll(command)
├── Tests/
│   └── MacHealthKitTests/                              # XCTest
│       ├── AppleScriptEscaperTests.swift
│       ├── JobCatalogTests.swift
│       ├── JobControllerSafetyTests.swift              #   注入耐性・フォールバックの境界
│       ├── JobControllerTests.swift                    #   CQRS の I/F 契約
│       ├── LogOpenInvocationTests.swift                #   openLog の touch → open 分割
│       ├── MenuModelTests.swift                        #   項目データの正しさ
│       ├── MetricsParserTests.swift                    #   丸め・単位・フォールバック
│       ├── ScheduleTimingTests.swift                   #   翌日繰上げ・相対時刻
│       ├── ShellRunnerContractTests.swift              #   引数配列の素通し
│       ├── SpyShellRunner.swift                        #   呼出を捕捉するスパイ
│       └── ZshShellRunnerInjectionTests.swift          #   `; rm -rf x` 等の引数注入が起きないこと
├── scripts/
│   ├── bin/                                            # launchd 起動対象・CLI
│   │   ├── mac-health                                  #   CLI: status/logs/events/enable/disable/test/run/uninstall
│   │   ├── monitor.sh                                  #   J4 PressureWatch（5 分毎）
│   │   ├── check-docker.sh                             #   J3 DockerIdleStop（10 分毎）
│   │   ├── check-uptime.sh                             #   J5 UptimeNudge（毎日 9:00）
│   │   ├── refresh.sh                                  #   J1 AppRefresh（毎日 3:00）
│   │   └── notification_cooldown.sh                    #   should_notify / classify_pressure / exceeds_threshold
│   ├── lib/                                            # 共通ユーティリティ（一方向依存）
│   │   ├── log.sh                                      #   log / log_event / rotate_logs / finalize_job / record_rotation_error
│   │   ├── notify.sh                                   #   notify（osascript） / is_business_hours
│   │   ├── metrics.sh                                  #   metrics_parse_* + metrics_*_raw/mb/gb + dispatch CLI
│   │   └── lock.sh                                     #   acquire_lock / release_lock / with_lock（mkdir ベース）
│   ├── config/
│   │   └── thresholds.sh                               #   閾値・ローテート・cooldown の編集可能設定
│   └── test/
│       ├── log_rotate.bats / log_rotate_test.sh        #   needs_rotation / next_generation / rotate_file
│       ├── metrics.bats   / metrics_test.sh            #   metrics_parse_* / metrics_uptime_*
│       └── monitor.bats   / monitor_test.sh            #   should_notify / classify_pressure / exceeds_threshold
├── launchagents/                                       # launchd ジョブ定義テンプレート（{{HOME}} プレースホルダ）
│   ├── com.github.adachi-tatsuru.machealth.monitor.plist.template   # StartInterval=300 / RunAtLoad=true
│   ├── com.github.adachi-tatsuru.machealth.docker.plist.template    # StartInterval=600 / RunAtLoad=false
│   ├── com.github.adachi-tatsuru.machealth.uptime.plist.template    # StartCalendarInterval Hour=9 Minute=0
│   └── com.github.adachi-tatsuru.machealth.refresh.plist.template   # StartCalendarInterval Hour=3 Minute=0
├── docs/                                               # システム仕様書（本ドキュメント群）
│   ├── README.md
│   ├── 00_review/                                      #   .gitkeep + YYYYMMDD_HHMMSS_review.md（レビュー記録）
│   ├── 01_システム概要/{README.md,01_プロジェクト概要/,02_ステークホルダー/,03_アーキテクチャ/,04_ディレクトリ構成/}
│   ├── 02_画面設計/README.md
│   ├── 03_データ設計/README.md
│   ├── 04_機能設計/{README.md,メニューバー表示/,メトリクス収集/,...}
│   ├── 05_エラー処理と外部通知/README.md
│   └── 99_ID命名規則と管理/README.md
├── .agents/                                            # 実行契約・規約（汎用テンプレート）
├── .agents-project/                                    # プロジェクト固有ルール（.agents より優先）
├── .workflow/                                          # ワークフロー成果物（issue・00〜04・templates・workflow.db）
├── Package.swift                                       # SwiftPM（テスト用 library + test target）
├── Makefile                                            # make test / test-swift / test-shell の集約
├── install.sh                                          # 配布（コピー + swiftc + .app 組立 + bootstrap + login item）
├── uninstall.sh                                        # 撤去（bootout + アプリ削除 + login item 削除 + 任意でログ削除）
├── README.md                                           # プロジェクト README
├── LICENSE                                             # MIT
├── AGENTS.md                                           # エージェント向け規約の入口
└── CLAUDE.md                                           # Claude Code 向け入口（.agents への参照）
```

---

## 4.8. ファイル別責務一覧（実装の細部まで）

### 4.8.1. `src/`（UI 層・AppKit 依存）

| ファイル | 責務（1〜2 行） | 関数・主要シンボル |
| -------- | -------------- | ------------------ |
| `src/MacHealth.swift` | `AppDelegate` + `@main MacHealthMain`。メニューバー UI とユーザー操作の調整役。各層へ委譲し自身はロジックを持たない。 | `applicationDidFinishLaunching` / `setStatusIcon` / `refreshMetricsAsync` / `rebuildMenu` / `refreshNow` / `quickAppRefresh` / `quickPurge` / `quickMemoryPressure` / `quickDockerQuit` / `toggleJob` / `runJob` / `pauseAllJobs` / `resumeAllJobs` / `openEventsLog` / `openMonitorLog` / `openLog(path:)` / `testNotification` / `showMetricsHelp` / `showAbout` / `notify(_:)` |
| `src/MenuBuilder.swift` | `[MenuItemSpec]` を NSMenu/NSMenuItem に変換する薄い AppKit 部。`MenuAction → Selector` の 1 対 1 マップ。 | `makeMenu(_:target:) -> NSMenu` / `Self.selector(for:)` / `NSMenuItem.toptip(_:)` |
| `src/MetricsCollector.swift` | 実コマンドを実行し `MetricsParser` に委譲して `MetricsSnapshot` を組み立てる（Imperative Shell）。`metrics.sh <metric>` 引数呼び出し + boot epoch / compressor 生ページ / docker count の 3 箇所のみ `shellFixed` で固定文字列残置。 | `metric(_:) -> String` / `shellFixed(_:) -> String` / `collect() -> MetricsSnapshot` |
| `src/Info.plist` | アプリの Info.plist。`CFBundleIdentifier=com.github.adachi-tatsuru.machealth.app`、`LSUIElement=true`、`LSMinimumSystemVersion=11.0`、`CFBundleVersion=1.2`。 | — |

### 4.8.2. `Sources/MacHealthKit/`（Domain + Infra・Foundation のみ）

| ファイル | 責務 | 主要シンボル |
| -------- | ---- | ------------ |
| `Metrics.swift` | 値型 `JobStatus`（loaded/lastRun/nextRun）と `MetricsSnapshot`（uptimeDays/Hours、loadAvg、memoryFreePct、compressedGB、swapUsed、dockerLine、jobs: \[String: JobStatus\]、lastUpdated）。 | `public struct JobStatus` / `public struct MetricsSnapshot` |
| `JobCatalog.swift` | ジョブ ID 並び（`monitor`/`docker`/`uptime`/`refresh`）・短名・頻度・スケジュール（`.interval(300)`/`.interval(600)`/`.daily(9,0)`/`.daily(3,0)`）・launchd ラベル規則 `com.github.adachi-tatsuru.machealth.<job>`。 | `public enum ScheduleKind { interval(Int) / daily(Int,Int) }` / `public struct JobCatalog` / `label(for:)` |
| `ScheduleTiming.swift` | 時刻計算の純粋ロジック。`now` を引数化しテスト可能。`Calendar.utc` テストヘルパ付属。 | `nextDailyRun(hour:minute:now:calendar:)` / `relativeTimeShort(_:now:)` / `relativeNext(_:intervalSec:now:calendar:)` |
| `MetricsParser.swift` | 文字列 → メトリクス値の純粋パース（trim・丸め・"%.1f GB"・"—" フォールバック）。 | `parseLoadAvg` / `parseSwapUsed` / `parseMemoryFreePct` / `uptimeDaysHours(bootEpoch:nowEpoch:)` / `uptimeDaysHours(bootString:nowEpoch:)` / `compressedGB(pages:)` / `dockerLine(running:containerCount:)` |
| `MenuModel.swift` | `MetricsSnapshot`/`JobStatus`/`JobCatalog` → `[MenuItemSpec]` 純粋生成。`MenuItemSpec`（kind/title/isEnabled/action/keyEquivalent/representedJob/tooltip）と `MenuAction` 列挙の定義。 | `MenuItemSpec` / `MenuAction` / `MenuModel.build(snapshot:catalog:timing:now:calendar:)` / `headerSpecs` / `metricsSpecs` / `quickActionSpecs` / `jobListSpecs` / `runJobSpecs` / `logSpecs` / `bulkSpecs` / `footerSpecs` |
| `AppleScriptEscaper.swift` | osascript への安全な値渡し。argv 渡し（推奨）と AppleScript リテラルエスケープ（フォールバック）。 | `notificationArgs(message:title:) -> (executable, args)` / `escapeForAppleScriptLiteral(_:) -> String` |
| `ShellRunner.swift` | `protocol ShellRunner` と既定実装 `ZshShellRunner`。`Process.executableURL + arguments` で引数配列のまま起動しシェル再パースを排除。失敗時 `""` を返す（現状互換）。 | `protocol ShellRunner.run(_:_:) -> String` / `final class ZshShellRunner` |
| `JobController.swift` | CQRS で `launchctl` を扱う。`isLoaded(job:)` は `launchctl list` を読み Swift 側でリテラル比較（query）。`load`/`unload`/`toggle`/`enableAll`/`disableAll` は bootstrap/bootout（失敗時 load/unload フォールバック）または CLI 呼出（command）。 | `isLoaded(job:)` / `load(job:)` / `unload(job:)` / `toggle(job:wasLoaded:)` / `enableAll()` / `disableAll()` / 内部 `bootstrapSucceeded(_:)` |

### 4.8.3. `scripts/bin/`（実行スクリプト・CLI）

| ファイル | 責務 | 主要シンボル / 入出力 |
| -------- | ---- | ------------------- |
| `scripts/bin/mac-health` | CLI エントリ。サブコマンドで状態確認・ログ表示・ジョブ ON/OFF・即実行・アンインストールを提供。`source` するのは `lib/log.sh` `lib/notify.sh` `lib/metrics.sh`。 | サブコマンド: `status` / `logs [N]` / `events` / `enable` / `disable` / `test` / `run {monitor\|docker\|uptime\|refresh}` / `uninstall` / それ以外でヘルプ |
| `scripts/bin/monitor.sh` | 5 分毎の PressureWatch。`$JOB=monitor`、`$COOLDOWN_FILE=$LOG_DIR/.monitor-cooldown`、`trap finalize_job EXIT`。閾値 4 種（swap/compressed/load/pressure）を判定し通知。 | `metrics_swap_used_mb` / `metrics_compressed_gb` / `metrics_load_1m` / `metrics_memory_free_pct` / `classify_pressure` / `exceeds_threshold` / `should_notify` |
| `scripts/bin/check-docker.sh` | 10 分毎の DockerIdleStop。`$STATE_FILE=$LOG_DIR/.docker-state`、`$COOLDOWN_FILE=$LOG_DIR/.docker-notify-cooldown`。コンテナ 0 が `DOCKER_IDLE_GRACE_MINUTES` 継続で業務時間外なら `quit Docker Desktop`、業務時間内なら通知（cooldown 21600 秒 = 6 時間ハードコード）。 | `pgrep` 起動判定 / `docker ps -q` 3 秒タイムアウト / `is_business_hours` / `notify` / `log_event` |
| `scripts/bin/check-uptime.sh` | 毎日 9:00 の UptimeNudge。`sysctl kern.boottime` → days を算出し `UPTIME_WARN_DAYS` 超過で通知。 | `sysctl -n kern.boottime` / `notify` / `log_event` |
| `scripts/bin/refresh.sh` | 毎日 3:00 の AppRefresh。`APPS=(Slack Chatwork "Google Chrome" Firefox Claude)` を順次 `quit saving no` → `wait_for_quit`（最大 30 秒）→ `open -a` 再起動。Cursor は除外。 | `is_running` / `quit_app`（osascript with timeout 15s）/ `wait_for_quit` / `refresh_app` |
| `scripts/bin/notification_cooldown.sh` | `monitor.sh` から source する純粋ロジック。クールダウン制御・閾値判定・メモリプレッシャー分類。`with_lock` で cooldown 更新を直列化。 | `should_notify <key>` / `_should_notify_update <key> <now>` / `exceeds_threshold <value> <threshold>` / `classify_pressure <free_pct>` |

### 4.8.4. `scripts/lib/`（共通ユーティリティ）

| ファイル | 責務 | 主要シンボル |
| -------- | ---- | ------------ |
| `scripts/lib/log.sh` | ログ書込（`log` / `log_event`）・サイズ世代ローテート（`rotate_logs` / `rotate_file`）・全ジョブ共通終了処理（`finalize_job`）。Functional Core（`needs_rotation` / `next_generation`）と Imperative Shell（`rotate_file_locked` / `rotate_logs`）を分離。 | `LOG_DIR=$HOME/Library/Logs/MacHealth` / `log` / `log_event` / `needs_rotation` / `next_generation` / `file_size_bytes` / `record_rotation_error` / `_max_existing_generation` / `rotate_file` / `_rotate_file_locked` / `rotate_logs` / `finalize_job` |
| `scripts/lib/notify.sh` | osascript によるデスクトップ通知発行と業務時間判定。 | `notify <title> <message> [subtitle]` / `is_business_hours`（08:00-21:59） |
| `scripts/lib/metrics.sh` | メトリクス取得の集約。純粋パース関数 `metrics_parse_*` と実コマンドラッパ `metrics_*_*`。`BASH_SOURCE` 判定で直接実行時のみ dispatch（Swift から `metrics.sh <metric>` で呼ぶ）。 | 純粋: `metrics_parse_swap_mb` / `metrics_parse_swap_raw` / `metrics_parse_compressed_gb` / `metrics_parse_load_1m` / `metrics_parse_load_1m_raw` / `metrics_parse_free_pct` / `metrics_uptime_days` / `metrics_uptime_hours`。ラッパ: `metrics_swap_used_mb` / `metrics_swap_used_raw` / `metrics_compressed_gb` / `metrics_load_1m` / `metrics_load_1m_raw` / `metrics_memory_free_pct` / `metrics_uptime_days_now` / `metrics_uptime_hours_now` / `metrics_docker_status`。dispatch: `load`/`swap`/`free`/`compressed`/`uptime_days`/`uptime_hours`/`docker` |
| `scripts/lib/lock.sh` | mkdir ベースの排他制御。`$LOG_DIR/.locks/<name>.lock` をロックパスにする固定方式。ロック取得失敗時はベストエフォートで継続。 | `_lock_base_dir` / `acquire_lock <name> [timeout_sec]` / `release_lock <name>` / `with_lock <name> <command...>` |

### 4.8.5. `scripts/config/`

| ファイル | 責務 | 主要変数（既定値） |
| -------- | ---- | ----------------- |
| `scripts/config/thresholds.sh` | 編集可能な設定値。各ジョブが source する。 | `THRESHOLD_SWAP_USED_MB=5000` / `THRESHOLD_COMPRESSED_GB=10` / `THRESHOLD_LOAD_AVG_MULTIPLIER=10`（コア数倍率）/ `DOCKER_IDLE_GRACE_MINUTES=30` / `UPTIME_WARN_DAYS=30` / `NOTIFICATION_COOLDOWN_MIN=60` / `MHK_ROTATE_MAX_BYTES=5242880`（5 MB）/ `MHK_ROTATE_KEEP_GENERATIONS=3` / `MHK_ROTATE_EXTS="log out err"` / `MHK_LOCK_TIMEOUT_SEC=5` |

### 4.8.6. `scripts/test/`

| ファイル | 責務 |
| -------- | ---- |
| `monitor.bats` / `monitor_test.sh` | `should_notify` / `classify_pressure` / `exceeds_threshold` の純粋ロジック検証。bats が無い環境では自前 assert ランナーが走る。 |
| `metrics.bats` / `metrics_test.sh` | `metrics_parse_*` / `metrics_uptime_*` の純粋ロジック検証。 |
| `log_rotate.bats` / `log_rotate_test.sh` | `needs_rotation` / `next_generation` / `rotate_file` の検証。 |

### 4.8.7. `launchagents/`

| ファイル | Label / 実行コマンド | スケジュール | RunAtLoad | StandardOutPath / ErrorPath |
| -------- | -------------------- | ------------ | --------- | --------------------------- |
| `com.github.adachi-tatsuru.machealth.monitor.plist.template` | `com.github.adachi-tatsuru.machealth.monitor` / `{{HOME}}/.local/bin/mac-health/bin/monitor.sh` | `StartInterval=300` | `true` | `{{HOME}}/Library/Logs/MacHealth/launchd.monitor.{out,err}` |
| `...docker.plist.template` | `....machealth.docker` / `…/check-docker.sh` | `StartInterval=600` | `false` | `launchd.docker.{out,err}` |
| `...uptime.plist.template` | `....machealth.uptime` / `…/check-uptime.sh` | `StartCalendarInterval Hour=9 Minute=0` | `false` | `launchd.uptime.{out,err}` |
| `...refresh.plist.template` | `....machealth.refresh` / `…/refresh.sh` | `StartCalendarInterval Hour=3 Minute=0` | `false` | `launchd.refresh.{out,err}` |

### 4.8.8. ルート・ビルド・配布

| ファイル | 責務 |
| -------- | ---- |
| `Package.swift` | SwiftPM 構成（**テスト専用**）。`MacHealthKit` library target（`path: "Sources/MacHealthKit"`）と `MacHealthKitTests` test target を定義。配布ビルドは `install.sh` 内 `swiftc`。 |
| `Makefile` | `make test`（XCTest 利用可なら `swift test` を実行・XCTest 不在なら skip、続けて test-shell。bats があれば bats、無ければ自前 `*_test.sh`）/ `make test-swift` / `make test-shell`。 |
| `install.sh` | 環境チェック → `scripts/` と `src/` をコピー → plist 実体化 → `swiftc` でビルド → `.app` 組立 → `launchctl bootstrap` → `open` 起動 → ログイン項目追加。冪等。 |
| `uninstall.sh` | ジョブ bootout → アプリ quit/削除 → ログイン項目削除 → `~/.local/bin/mac-health/` 削除 → ログ削除を対話確認。 |
| `README.md` | プロジェクトの README（インストール・使い方・配布の概要）。 |
| `LICENSE` | MIT License。 |
| `AGENTS.md` | エージェント向け規約の入口（`.agents/` への参照）。 |
| `CLAUDE.md` | Claude Code 向け入口（`.agents/` および `.agents-project/` への参照）。 |

### 4.8.9. ドキュメント・規約

| ファイル / ディレクトリ | 責務 |
| ----------------------- | ---- |
| `docs/` | システム仕様書（本書）。`00_review/` にレビュー結果を記録（DOCS_RULES）。 |
| `.agents/` | 実行契約・spec（01〜06）・commands・skills・agents・boot・workflow・scripts。 |
| `.agents-project/` | プロジェクト固有ルール。`.agents` と同名・同目的は `.agents-project/` が優先。 |
| `.workflow/` | issue 群（`YYYYMMDD_HHMMSS_<title>/`・親 + 90_issues サブ）・templates・workflow.db。 |

---

## 4.9. 配置物の実行時所在（インストール後）

| 種別 | 実行時パス（`$HOME` 表記） | 役割 |
| ---- | -------------------------- | ---- |
| アプリ | `$HOME/Applications/MacHealth.app/Contents/{MacOS/MacHealth,Info.plist}` | メニューバー本体。LSUIElement=true。 |
| CLI / スクリプト | `$HOME/.local/bin/mac-health/{bin,lib,config,src}` | install.sh が配置。Swift も `metricsShPath = ~/.local/bin/mac-health/lib/metrics.sh` を参照。 |
| LaunchAgent | `$HOME/Library/LaunchAgents/com.github.adachi-tatsuru.machealth.<job>.plist` | `{{HOME}}` を `$HOME` 展開後の plist（4 本）。 |
| ログ | `$HOME/Library/Logs/MacHealth/{events.log,<job>.log,launchd.<job>.{out,err},rotate.err,.monitor-cooldown,.docker-state,.docker-notify-cooldown,.locks/<name>.lock}` | 通知履歴・各ジョブログ・launchd 出力・ローテートエラー・cooldown・状態・ロック。 |

---

## 参考資料

- [01 システム概要](../README.md)
- [03 アーキテクチャ](../03_アーキテクチャ/README.md)
- [03 データ設計](../../03_データ設計/README.md)
- [04 機能設計](../../04_機能設計/README.md)
- `.agents/spec/02_ディレクトリ構造方針.md`、`.agents/spec/03_命名規則.md`

---

**最終更新**: 2026 年 05 月 28 日 / **maintainer**: docs worker
