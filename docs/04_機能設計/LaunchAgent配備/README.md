---
document_id: "A788EB9C-0EFF-4A87-A441-38F98C4AFAD3"
---

このドキュメントは、LaunchAgent 配備機能（install/uninstall）の設計を定義します。

# LaunchAgent 配備機能（F008）

## 概要

`install.sh` がアプリ・スクリプト・LaunchAgent plist を実環境へ配置し、`launchctl bootstrap` で 4 ジョブを `gui/<uid>` ドメインへ登録する。`uninstall.sh` は逆順に撤去する。

## install.sh の処理フロー

```mermaid
sequenceDiagram
    participant U as ユーザー
    participant SH as install.sh
    participant ENV as 環境チェック
    participant CP as cp -R
    participant SED as sed (plist 実体化)
    participant SC as swiftc
    participant LCTL as launchctl
    participant SE as System Events

    U->>SH: ./install.sh
    SH->>ENV: OSTYPE darwin* / swiftc / osascript
    ENV-->>SH: OK
    SH->>CP: scripts/{bin,lib,config}, src/ を ~/.local/bin/mac-health/{bin,lib,config,src}
    CP-->>SH: 完了
    SH->>SED: launchagents/*.plist.template の {{HOME}} を $HOME に展開し ~/Library/LaunchAgents/ へ
    SED-->>SH: plist 4 本
    SH->>SH: mkdir -p ~/Library/Logs/MacHealth
    SH->>SC: swiftc src/MacHealth.swift MetricsCollector.swift MenuBuilder.swift + Sources/MacHealthKit/*.swift (8 ファイル) -o MacHealth
    SC-->>SH: バイナリ
    SH->>SH: mkdir -p ~/Applications/MacHealth.app/Contents/{MacOS,Resources}
    SH->>SH: cp MacHealth → Contents/MacOS / Info.plist → Contents/
    loop 4 ジョブ
        SH->>LCTL: bootout gui/$UID/$label || true
        SH->>LCTL: bootstrap gui/$UID $plist (失敗時 load $plist)
        SH->>LCTL: list | grep $label で確認
    end
    SH->>SH: open ~/Applications/MacHealth.app
    SH->>SH: pgrep -f MacHealth.app/Contents/MacOS/MacHealth (起動確認)
    SH->>SE: make login item path:APP_DIR hidden:true (未登録時のみ)
    SH-->>U: 完了メッセージ
```

## uninstall.sh の処理フロー

```mermaid
sequenceDiagram
    participant U as ユーザー
    participant SH as uninstall.sh
    participant LCTL as launchctl
    participant OS as osascript
    participant SE as System Events
    participant FS as ファイルシステム

    U->>SH: ./uninstall.sh
    loop 4 ジョブ
        SH->>LCTL: bootout gui/$UID/$label || true
        SH->>LCTL: unload $plist || true
        SH->>FS: rm $plist
    end
    SH->>OS: quit app "Mac Health"
    SH->>FS: pkill -f MacHealth.app/Contents/MacOS/MacHealth
    SH->>FS: rm -rf ~/Applications/MacHealth.app
    SH->>SE: delete login item "MacHealth"
    SH->>FS: rm -rf ~/.local/bin/mac-health
    SH->>U: ログ削除しますか？ [y/N]
    alt yes
        SH->>FS: rm -rf ~/Library/Logs/MacHealth
    end
```

## ビルド内訳（`install.sh` 内 `swiftc`）

`install.sh` 内で **1 モジュールとして** 以下 11 ファイルを `swiftc` に渡す（順序は実物どおり）。

| グループ | ファイル |
| -------- | -------- |
| UI（src/） | `MacHealth.swift` / `MetricsCollector.swift` / `MenuBuilder.swift` |
| Kit（Sources/MacHealthKit/） | `ScheduleTiming.swift` / `Metrics.swift` / `JobCatalog.swift` / `MetricsParser.swift` / `MenuModel.swift` / `ShellRunner.swift` / `AppleScriptEscaper.swift` / `JobController.swift` |

> `src/` の Swift ファイルでは `import MacHealthKit` は **不要**。`swiftc` ビルドでは src/Sources を 1 モジュールとしてまとめてコンパイルするため、型は同一モジュール内で解決される。

## 関係モジュール

| ファイル | 役割 |
| -------- | ---- |
| `install.sh` | 配備本体（環境チェック・コピー・plist 実体化・ビルド・bootstrap・ログイン項目）。 |
| `uninstall.sh` | 撤去本体（bootout・アプリ削除・ログイン項目削除・対話的ログ削除）。 |
| `launchagents/*.plist.template` | `{{HOME}}` プレースホルダ付き plist テンプレート。 |
| `src/Info.plist` | アプリの Info.plist（LSUIElement=true 等）。 |
| `Package.swift` | テスト用 SwiftPM 構成（配布ビルドでは使わない）。 |
| `Makefile` | テスト集約（配布には使わない）。 |

## 関連テスト

- `install.sh` / `uninstall.sh` は実環境変更を伴うため XCTest 対象外。手動検証で配備の動作を確認する（`launchctl list | grep machealth` / `open ~/Applications/MacHealth.app` 等）。

## 既知の制約

- `xcode-select --install` が完了していない環境では `swiftc` が無く `install.sh` の環境チェックで停止する。
- ログイン項目登録は `osascript` 経由のため、Automation 権限ダイアログが初回に表示される（macOS の TCC）。
- `bootstrap` に失敗した場合のフォールバックは `launchctl load`。これでも失敗するとそのジョブは `⚠️` で表示するが install 自体は継続する（部分的失敗を許容）。
- `~/Library/Logs/MacHealth/` を残したまま `uninstall.sh` 後に再 `install.sh` した場合、ローテート世代ファイル（`*.log.N`）が残る。意図的にクリーンインストールしたい場合は uninstall 時にログを削除する選択をする。

---

## 参考資料

- [03 アーキテクチャ §3.8 ビルド／配備フロー](../../01_システム概要/03_アーキテクチャ/README.md#38-ビルド--配備フロー)
- [03 データ設計 §3.4 launchd plist スキーマ](../../03_データ設計/README.md#34-launchd-plist-スキーマ)
- 一次情報: `install.sh`・`uninstall.sh`・`launchagents/*.plist.template`・`src/Info.plist`

---

**最終更新**: 2026 年 05 月 28 日 / **maintainer**: docs worker
