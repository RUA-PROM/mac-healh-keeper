# PR #3 マージ後の install 実機検証ログ

- **対象 issue**: `.workflow/close/20260529_105524_ビルド時バージョン自動stamp/`（close 済み）
- **目的**: PR #3 (`d41ed02` Merge pull request #3 from RUA-PROM/feature/20260529) を main にマージ・同期した直後の、ローカル `./install.sh` 実機検証フォローアップ。close 済み issue（ビルド時バージョン自動 stamp / 警告バナー機構 / pure-core テストランナー / smoke・version_stamp テスト導入）の受け入れ基準が、実機の `~/Applications/MacHealth.app` 上でも成立することを確認する。
- **ブランチ**: main（`d41ed02`）
- **作業ツリー**: クリーン

## 事前状態

| 項目 | 値 |
|---|---|
| `~/Applications/MacHealth.app/Contents/MacOS/MacHealth` mtime | 5/29 08:45 |
| バイナリサイズ | 276,152 bytes |
| `CFBundleVersion` (旧) | `1.2` |
| `CFBundleShortVersionString` (旧) | `1.2` |
| 稼働中プロセス (旧) | PID **84455** |
| `git describe --tags --always` | `v20260529.120703` |
| HEAD | `d41ed02` (Merge PR #3) |

> 旧 .app は PR #3 マージ前のバイナリ。`CFBundleVersion=1.2` で stamp 機構未適用。

## install 実行ログ要点（1 回目）

- コマンド: `bash /Volumes/ssd-01/NextCloud/Documents/各案件管理/builtfunc/mac-health-keeper/install.sh`
- 終了コード: **0**
- 所要時間: **約 12 秒**
- swiftc: Apple Swift 6.2.4 で **284,016 bytes** のバイナリをビルド成功
- `.app` 配置: `/Users/adachiken/Applications/MacHealth.app`
- `version_stamp.sh` の stamp 値: **`v20260529.120703`**（= `git describe --tags --always` と一致）
- LaunchAgent ロード状況:
  - `com.github.adachi-tatsuru.machealth.monitor.plist`: 警告（ロード失敗）
  - `com.github.adachi-tatsuru.machealth.docker.plist`: 警告（ロード失敗）
  - `com.github.adachi-tatsuru.machealth.uptime.plist`: ロード成功
  - `com.github.adachi-tatsuru.machealth.refresh.plist`: 警告（ロード失敗）
  - **既知の uptime/refresh/monitor/docker LaunchAgent ロード失敗事象は別 issue 候補として残置（本検証では観測のみ）**
- アプリ起動: 成功（メニューバーに 🩺 アイコン）
- ログイン項目: 既登録

## 事後検証

### A. バージョン stamp の正しさ（UC1）

```
expected=v20260529.120703
actual  =v20260529.120703
STAMP MATCH
```

- `CFBundleVersion` は `git describe --tags --always` 出力と一致
- `0.0.0-DEV` の残置なし → stamp 機構は正常に動作

### B. semver の維持

- `CFBundleShortVersionString = 1.3` を確認（spec 通り）
- About アラート文言の動的取得（`Bundle.main.infoDictionary["CFBundleShortVersionString"]`）が現バイナリで `1.3` を返す状態

### C. プロセス再起動の確認

- install 前 PID: **84455** (5/29 08:45 ビルド, 276,152 bytes)
- install 後 PID: **77028** (5/29 12:10 ビルド, 284,016 bytes)
- PID 変化・mtime 更新・サイズ変化を確認 → 新バイナリで起動済み

### D. close 済み issue 受け入れ基準（テスト）

| テスト | 結果 |
|---|---|
| `scripts/test/install_metrics_smoke_test.sh` | **8 passed, 0 failed**（UC1-S1/S2, UC2-S1, UC3-S1×3）|
| `scripts/test/version_stamp_test.sh` | **10 passed, 0 failed**（UC1-S1×2, UC1-S2, UC2-S1×2, UC3-S1×2, UC3-S2, UC3-S3×2）|

### E. install 2 回連続実行のべき等性（任意）

- 2 回目 install: 終了コード **0**、所要 **約 10 秒**
- 2 回目 `CFBundleVersion`: `v20260529.120703`（**1 回目と一致**）
- 2 回目 PID: 77028 → **80556**（再起動は実施されるが stamp は同 commit のため不変）
- 受け入れ基準（案 Y UC1）「同 commit から install すれば誰がいつ install しても同じ値」を満たす

## GUI 目視確認（ユーザー側依頼）

CLI からは触れない以下の項目はユーザー側で確認をお願いします。

- メニューバー 🩺 アイコン → メニュー表示
- 「About」アラートのバージョン文字列が **「バージョン 1.3」** と表示されること（旧 1.2 ではないこと）
- 負荷（load 1m）・空きメモリ・スワップ使用量 が数値として表示されていること
- メトリクス取得不可時の警告バナー（MenuModel エラー表示）の挙動は通常運用では発火しにくいので任意

## 残課題 / 既知事象

1. **LaunchAgent monitor/docker/refresh のロード失敗（再現）**
   - 本 install 実行でも同じ警告が出力された
   - close 済み先行 issue で「別 issue 候補として残置」と整理済み
   - 本依頼の範囲外（深追いせず観測のみ）
2. 警告バナー機構の実機トリガはユーザー目視確認の範囲

## 結論

- PR #3 マージ後の `./install.sh` は **エラーなく完了**し、`CFBundleVersion` は `git describe --tags --always` と一致した値で stamp された
- close 済み issue「ビルド時バージョン自動 stamp」の受け入れ基準（UC1〜UC3）は実機でも満たされている
- `CFBundleShortVersionString=1.3` 維持、プロセス再起動、テスト群 PASS、べき等性も成立
- 残る確認は GUI（About アラート文言・メニュー表示）のユーザー目視のみ
