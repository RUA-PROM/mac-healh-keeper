# 🩺 Mac Health Keeper

> **再起動なしで「再起動相当のクリーンさ」を保つ Mac 自動メンテシステム**

長時間 Mac を起動しっぱなしにすると、Electron アプリ群のメモリリーク、Docker Desktop の空回り、ファイルシステムキャッシュの蓄積などでだんだん重くなります。Mac Health Keeper は **再起動の必要性そのものを発生させない** アプローチで、これらを自動的に予防します。

**メニューバー常駐のネイティブ macOS アプリ + 4 つの自動ジョブ** で構成されています。

---

## 🌟 特徴

- 🩺 **メニューバー常駐** ― ライト/ダークモード自動追従の SF Symbols アイコン
- 🇯🇵 **完全日本語 UI**
- 🔄 **ワンクリックでジョブ ON/OFF**
- 📊 リアルタイムのメトリクス表示（メモリ・スワップ・Load Avg・Docker 状態）
- 💸 **完全無料**、追加の課金やクラウド連携なし
- 🪶 **超軽量** ― 常駐コストはごくわずか
- 🧹 **自動メンテ** ― ユーザー操作不要

---

## 📦 何をしてくれるのか

| ジョブ | 頻度 | 内容 |
|---|---|---|
| **メモリ／負荷監視** | 5 分毎 | メモリ free %、圧縮メモリ、Load Avg、スワップを監視し、閾値超過で通知 |
| **Docker アイドル監視** | 10 分毎 | Docker Desktop がコンテナ無しで 30 分継続したら、業務時間外なら自動 Quit、業務時間内なら通知 |
| **長期稼働の通知** | 毎日 09:00 | uptime 30 日超で月 1 回程度の再起動を控えめに通知 |
| **アプリ自動再起動** | 毎日 03:00 | Slack / Chatwork / Chrome / Firefox / Claude を順次再起動。メモリリーク累積をリセット |

---

## 🚀 インストール

### 前提条件
- macOS 11 (Big Sur) 以降
- Xcode Command Line Tools（`xcode-select --install`）

### ワンライン

```bash
git clone https://github.com/adachi-tatsuru/mac-health-keeper.git
cd mac-health-keeper
./install.sh
```

インストーラがやってくれること：
1. 環境チェック（macOS / Swift）
2. スクリプトを `~/.local/bin/mac-health/` に配置
3. LaunchAgent plist を `~/Library/LaunchAgents/` に配置
4. Swift をビルドして `~/Applications/MacHealth.app` を作成
5. 4 つのジョブを `launchctl` でロード
6. アプリ起動
7. **ログイン項目に追加（自動起動）**

完了したらメニューバー右上に 🩺 アイコンが現れます。

---

## 🖱 使い方（メニューバー）

🩺 アイコンをクリックすると：

```
Mac Health Keeper
───────────────────
  稼働時間:       2日 4時間
  負荷平均(1分):  3.5
  空きメモリ:     66%
  圧縮メモリ:     2.1 GB
  スワップ使用:   0.00M
  Docker:         停止中
───────────────────
ジョブ（クリックで切替）
  ✓ メモリ／負荷監視     （5分毎）
  ✓ Dockerアイドル監視  （10分毎）
  ✓ 長期稼働の通知       （毎日 9:00）
  ✓ アプリ自動再起動     （毎日 3:00）
───────────────────
今すぐ実行
  ▶ メモリ／負荷監視
  ▶ Dockerアイドル監視
  ▶ 長期稼働の通知
  ▶ アプリ自動再起動
───────────────────
通知履歴を開く          ⌘E
監視ログを開く          ⌘M
通知テスト              ⌘T
───────────────────
全ジョブを停止
全ジョブを再開
───────────────────
このアプリについて…
Mac Health を終了        ⌘Q
```

各メニュー項目はワンクリックで動作します。**メニューは 60 秒毎に自動更新** されます。

---

## 🛠 CLI

```bash
~/.local/bin/mac-health/bin/mac-health status     # 現状サマリ
~/.local/bin/mac-health/bin/mac-health logs       # 監視ログ
~/.local/bin/mac-health/bin/mac-health events     # 通知履歴
~/.local/bin/mac-health/bin/mac-health test       # 通知テスト
~/.local/bin/mac-health/bin/mac-health run refresh   # 手動キック
~/.local/bin/mac-health/bin/mac-health disable    # 全ジョブ停止
~/.local/bin/mac-health/bin/mac-health enable     # 全ジョブ再開
~/.local/bin/mac-health/bin/mac-health uninstall  # アンインストール
```

---

## ⚙ カスタマイズ

閾値設定: `~/.local/bin/mac-health/config/thresholds.sh`

```bash
THRESHOLD_SWAP_USED_MB=5000             # スワップ使用量 (MB) これを超えたら警告
THRESHOLD_COMPRESSED_GB=10              # 圧縮メモリ (GB)
THRESHOLD_LOAD_AVG_MULTIPLIER=10        # Load Avg がコア数の何倍を超えたら警告
DOCKER_IDLE_GRACE_MINUTES=30            # コンテナなしで起動してからこの分数経過で対象
UPTIME_WARN_DAYS=30
NOTIFICATION_COOLDOWN_MIN=60
```

App Refresh の対象アプリは `scripts/bin/refresh.sh` 内の `APPS` 配列を編集してください（デフォルト: Slack / Chatwork / Google Chrome / Firefox / Claude）。

業務時間の定義は `scripts/lib/notify.sh` の `is_business_hours` 関数（既定: 8:00–22:00）。

---

## 📂 ファイル構成（インストール後）

| パス | 内容 |
|---|---|
| `~/Applications/MacHealth.app` | メニューバーアプリ |
| `~/.local/bin/mac-health/bin/` | CLI とジョブスクリプト |
| `~/.local/bin/mac-health/lib/` | 共通ライブラリ |
| `~/.local/bin/mac-health/config/thresholds.sh` | 閾値設定 |
| `~/.local/bin/mac-health/src/` | Swift ソースとビルド成果物 |
| `~/Library/LaunchAgents/com.github.adachi-tatsuru.machealth.*.plist` | LaunchAgent 定義 |
| `~/Library/Logs/MacHealth/` | ログ（14 日保持） |

---

## 🗑 アンインストール

```bash
cd mac-health-keeper
./uninstall.sh
```

LaunchAgent、アプリ、スクリプト、ログイン項目すべてが綺麗に削除されます。

---

## ⚠ 既知の制約

- **完全にリセットできないもの**：スワップアウト累積、`WindowServer` / `coreaudiod` の肥大化、カーネル状態
- これらは「長期稼働の通知」が控えめに知らせます。月 1 回程度の手動再起動推奨

---

## 🤔 設計コンセプト

「**再起動が必要になる前に予防する**」アプローチ：

- メモリリーク → アプリ単位で毎晩リフレッシュ
- アイドル Docker → 自動 Quit
- 異常な負荷 → 通知して気付く

結果としてスワップアウトがほぼ発生せず、再起動を要する状況が起きにくくなります。

---

## 🧪 開発・テスト

純粋ロジック（時刻計算・通知クールダウン・閾値判定・メトリクス取得）を単体テストで保護しています。Swift は XCTest（SwiftPM）、シェルは bats（不在時は自前 assert にフォールバック）で検証します。

生メトリクス取得（swap / 圧縮メモリ / Load Avg / メモリ空き率 / 稼働時間 / Docker）は `scripts/lib/metrics.sh` に集約し、`scripts/bin/mac-health`（status）と `scripts/bin/monitor.sh` が source して参照します。`metrics.sh` は「メトリクス取得」の単一責務に閉じ、閾値判定・通知・ログは含めません（純粋パース関数を `scripts/test/metrics.bats` / `metrics_test.sh` で固定入力検証）。

### テスト実行

```bash
make test          # Swift（swift test）とシェルテストをまとめて実行
make test-swift    # Swift（XCTest）のみ
make test-shell    # シェルテストのみ
```

`make test` は `swift test` を実行した後、`bats` が入っていれば `bats scripts/test/`（`*.bats` を自動走査）、入っていなければ自動で自前 assert ランナー（`bash scripts/test/monitor_test.sh` と `bash scripts/test/metrics_test.sh`）にフォールバックします。いずれかのテストが失敗すると非 0 終了します。

### bats の導入（任意）

```bash
brew install bats-core
```

bats が無い環境でもシェルテストは自前 assert ランナーで実行できるため、導入は任意です。

### 追加ディレクトリ構成（開発用）

| パス | 内容 |
|---|---|
| `Sources/MacHealthKit/` | AppKit 非依存の純粋ロジック（`ScheduleTiming`）。`swift test` と配布ビルド（install.sh の swiftc）の両方から参照される |
| `Tests/MacHealthKitTests/` | XCTest（`ScheduleTiming` の UC1/UC2） |
| `scripts/test/` | シェルテスト（`monitor.bats` / `monitor_test.sh` で `notification_cooldown.sh` の UC3/UC4、`metrics.bats` / `metrics_test.sh` で `metrics.sh` の UC1/UC2） |
| `Package.swift` | SwiftPM 構成（テスト専用。配布ビルドには使わない） |
| `Makefile` | `make test` でテスト一式を実行 |

> SwiftPM の生成物（`.build/`）と `Package.swift` は配布物には含めません。配布ビルドは従来どおり install.sh の `swiftc` を使います。

---

## 📜 License

[MIT](LICENSE)

---

## 🙏 Acknowledgements

このプロジェクトは「Mac が常にクリーンな状態であってほしい」という願いから、Claude との対話設計を経て生まれました。
