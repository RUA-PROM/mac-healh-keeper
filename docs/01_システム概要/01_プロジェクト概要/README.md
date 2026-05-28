---
document_id: "4238B6D3-C4BD-4A8B-BB4A-BF9967FC57FD"
---

このドキュメントは、Mac Health Keeper のプロジェクト概要（目的・スコープ・成果物・技術スタック・配布形態）を定義します。
システム仕様書作成ルールは [`.agents/DOCS_RULES.md`](../../../.agents/DOCS_RULES.md) を参照してください。

> 本ドキュメントは「生きているドキュメント」です。実装変更時に更新し、レビュー結果は [`docs/00_review/`](../../00_review/) に記録します。

# 1. プロジェクト概要

## 1.1. プロジェクト名・目的

- **プロジェクト名**: Mac Health Keeper
- **キャッチコピー**: 再起動なしで「再起動相当」の状態を保つ自動メンテナンスシステム（`src/MacHealth.swift` の `showAbout` 文言と一致）
- **目的**:
  - 長期間稼働させた macOS で発生する **メモリ枯渇・圧縮メモリ累積・スワップ蓄積・高負荷・Docker アイドル放置・長期 uptime** を、ユーザーが意識しなくても観測・通知・自動整理する。
  - メニューバーから現在の Mac の「健康状態」と各監視ジョブの状態を一目で把握し、必要なら即時にクイック対処を実行できるようにする。
  - 完全にローカルで完結し、外部サービスへ何も送信しない（個人マシン向け）。

## 1.2. スコープ（対象範囲）

### スコープ内（v1.2 時点で実装済み）

| 区分 | 機能 | 実装 |
| ---- | ---- | ---- |
| 監視 | メモリ／負荷監視（5 分毎） | `scripts/bin/monitor.sh` + `launchagents/...monitor.plist.template`（`StartInterval=300`）|
| 監視 | Docker アイドル監視（10 分毎） | `scripts/bin/check-docker.sh` + `...docker.plist.template`（`StartInterval=600`） |
| 監視 | 長期稼働の通知（毎日 9:00） | `scripts/bin/check-uptime.sh` + `...uptime.plist.template`（`StartCalendarInterval Hour=9 Minute=0`） |
| 自動整理 | アプリ自動再起動（毎日 3:00） | `scripts/bin/refresh.sh` + `...refresh.plist.template`（`StartCalendarInterval Hour=3 Minute=0`） |
| UI | メニューバー常駐アプリ | `src/MacHealth.swift`（`LSUIElement=true`）。ステータスアイコン → NSMenu でメトリクス・ジョブ・クイック対処を提供。 |
| UI | クイック対処（4 種） | AppRefresh 即実行 / `sudo purge`（確認ダイアログ）/ memory_pressure / Docker Desktop Quit |
| ジョブ制御 | ON/OFF トグル・全停止/全再開・即実行 | `Sources/MacHealthKit/JobController.swift`（CQRS） + `scripts/bin/mac-health` CLI |
| 通知 | 注入耐性のあるデスクトップ通知 | `Sources/MacHealthKit/AppleScriptEscaper.swift`（argv 渡し）／`scripts/lib/notify.sh` |
| ログ | サイズ世代ローテート＋排他制御 | `scripts/lib/log.sh`（`rotate_logs`） + `scripts/lib/lock.sh`（`with_lock`） |
| 配布 | 手動インストーラ／アンインストーラ | `install.sh` / `uninstall.sh`（`~/.local/bin/mac-health/`・`~/Applications/MacHealth.app`・`~/Library/LaunchAgents/`） |

### スコープ外（明示）

- マルチユーザー／システム全体（root）スコープでの動作。すべて `gui/<uid>` ドメインの LaunchAgent。
- 外部サービス連携（Slack / Rollbar / Datadog 等）。デスクトップ通知のみ。
- macOS App Store 配布（コード署名・公証は行わない）。
- 自動アップデート機能。アップデートは `install.sh` の再実行で行う。

## 1.3. 成果物・ドキュメント

| 種別 | 場所 | 内容 |
| ---- | ---- | ---- |
| アプリ本体 | `~/Applications/MacHealth.app` | メニューバーアプリ（CFBundleIdentifier `com.github.adachi-tatsuru.machealth.app`、`Info.plist` 参照）。 |
| スクリプト | `~/.local/bin/mac-health/{bin,lib,config}` | CLI `mac-health`・各ジョブスクリプト・共通ライブラリ・閾値設定。 |
| LaunchAgent | `~/Library/LaunchAgents/com.github.adachi-tatsuru.machealth.<job>.plist` | monitor / docker / uptime / refresh の 4 本。`{{HOME}}` を `install.sh` が `$HOME` に展開。 |
| ログ | `~/Library/Logs/MacHealth/` | `events.log`（通知履歴）／`<job>.log`（各ジョブ）／`launchd.<job>.{out,err}`（launchd 標準出力／エラー）／`rotate.err`（ローテート失敗）。 |
| 仕様書 | `docs/`（本ドキュメント群） | 「生きているドキュメント」。実装変更時に更新し `docs/00_review/` に整合性確認を記録。 |
| AI／開発規約 | `.agents/` / `.agents-project/` / `.workflow/` | 実行契約・spec・command・skill・テンプレート・ワークフロー成果物。 |
| 開発フロー | `Makefile`（`make check`）・`scripts/lint/`・`.github/workflows/{check.yml,create-release.yaml}` | ローカル検証（lint / format / 循環 / セキュリティ / test）と CI / Release 自動化。配布物には含まない（[04 機能設計 / ローカル検証](../../04_機能設計/ローカル検証/README.md)・[04 機能設計 / CI・Release 自動化](../../04_機能設計/CI・Release自動化/README.md)）。 |

## 1.4. 技術スタック

| カテゴリ | 技術 | バージョン | 用途 | 一次情報 |
| -------- | ---- | ---------- | ---- | -------- |
| 言語（アプリ） | Swift | 5.7+ | アプリ本体・MacHealthKit。 | `Package.swift`（`swift-tools-version:5.7`） |
| UI | AppKit / Cocoa | macOS SDK | メニューバー常駐 UI。`src/MacHealth.swift`・`src/MenuBuilder.swift`。 | `LSUIElement=true`（`src/Info.plist`） |
| ドメイン / Infra | Foundation のみ | macOS SDK | `Sources/MacHealthKit/` の唯一の依存（AppKit 非依存）。 | `Package.swift` |
| ビルド | Swift Package Manager / `swiftc` | - | テスト用に SwiftPM、配布は `install.sh` 内の `swiftc` 直接コンパイル。 | `Package.swift`・`install.sh` |
| ジョブ言語 | bash | macOS 同梱 | `scripts/bin/*`・`scripts/lib/*`・`scripts/config/*` の shebang は `#!/bin/bash`。 | 各 `.sh` 先頭 |
| スケジューラ | launchd | macOS 同梱 | `StartInterval` / `StartCalendarInterval` でジョブ起動。 | `launchagents/*.plist.template` |
| 通知 | osascript（AppleScript） | macOS 同梱 | デスクトップ通知発行。Swift 側は `AppleScriptEscaper` で argv 渡し、シェル側は `notify.sh`。 | `Sources/MacHealthKit/AppleScriptEscaper.swift`・`scripts/lib/notify.sh` |
| メトリクス取得 | `sysctl` / `vm_stat` / `uptime` / `memory_pressure` / `pgrep` / `docker` | macOS 同梱・任意 | `scripts/lib/metrics.sh` が一元化。Swift は `metrics.sh <metric>` を引数呼び出し。 | `scripts/lib/metrics.sh`・`src/MetricsCollector.swift` |
| テスト | XCTest（Swift） / bats / 自前 `*_test.sh`（シェル） | - | `Tests/MacHealthKitTests/`・`scripts/test/`。`make test` で集約。 | `Makefile`・`Package.swift` |
| 検証ツール | `shellcheck`（必須） / `shfmt` / `swift-format` / `swiftlint`（任意） | Homebrew | `make check` から `scripts/lint/run-*.sh` 経由で実行。任意ツール未導入は SKIP。 | `Makefile`・`scripts/lint/*` |
| CI / Release | GitHub Actions（`macos-latest` / `ubuntu-latest`） | - | PR / `main` push で `make check`、`main` マージで JST 日時タグ + `gh release --generate-notes`。 | `.github/workflows/{check.yml, create-release.yaml}` |

## 1.5. 対応 OS / 動作要件

- **macOS**: 11.0 以上（`Info.plist` の `LSMinimumSystemVersion=11.0`）。
- **Swift Toolchain**: `swiftc`（Command Line Tools または Xcode）。`install.sh` の環境チェックで検証。
- **osascript**: macOS 標準同梱（通知・AppleScript 実行に必須）。
- **Docker Desktop**: 任意。インストールされていれば監視・自動 Quit が機能。未導入なら docker 監視は「Docker not running」と記録するのみで停止しない。
- **Apple Silicon / Intel**: 両対応（`swiftc` のターゲットに依存。`install.sh` は `xcode-select --install` を前提）。

## 1.6. 配布形態

- **手動インストール**: GitHub からリポジトリを取得し `./install.sh` を実行する。App Store 配布・自動更新・コード署名は対象外（スコープ外）。
- **`install.sh` が行うこと**: 環境チェック → `scripts/` を `~/.local/bin/mac-health/` へコピー → LaunchAgent plist を `{{HOME}}` 展開して `~/Library/LaunchAgents/` に配置 → `swiftc` で 11 ファイル（`src/*.swift` 3 ＋ `Sources/MacHealthKit/*.swift` 8）を 1 モジュールとしてコンパイル → `~/Applications/MacHealth.app` を組立 → `launchctl bootstrap` で 4 ジョブをロード → `osascript` でログイン項目に追加。
- **`uninstall.sh` が行うこと**: 4 ジョブを `launchctl bootout` → アプリ Quit・削除 → ログイン項目から削除 → `~/.local/bin/mac-health/` を削除 → ログ削除を対話確認。
- **再インストール／アップデート**: `install.sh` の再実行で既存ジョブを bootout 後に bootstrap し直す（冪等）。

## 1.7. ライセンス

- **ライセンス**: MIT License（リポジトリ直下 `LICENSE` を参照）。
- **コピーライト**: `© 2026 RUA PROM`（`src/Info.plist` の `NSHumanReadableCopyright`）。

---

## 参考資料

- [02 ステークホルダー](../02_ステークホルダー/README.md)
- [03 アーキテクチャ](../03_アーキテクチャ/README.md)
- [04 ディレクトリ構成](../04_ディレクトリ構成/README.md)
- [04 機能設計](../../04_機能設計/README.md)
- [99 ID 命名規則と管理](../../99_ID命名規則と管理/README.md)

---

**最終更新**: 2026 年 05 月 28 日 / **maintainer**: docs worker
