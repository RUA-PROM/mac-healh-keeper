#!/bin/bash
# Mac Health Keeper - 閾値設定（編集可）

# メモリ枯渇通知の閾値
THRESHOLD_SWAP_USED_MB=5000             # スワップ使用量 (MB) これを超えたら警告
THRESHOLD_COMPRESSED_GB=10              # 圧縮メモリ (GB)
THRESHOLD_LOAD_AVG_MULTIPLIER=10        # Load Avg がコア数の何倍を超えたら警告

# Docker アイドル判定
DOCKER_IDLE_GRACE_MINUTES=30            # コンテナなしで起動してからこの分数経過で対象に

# uptime 警告
UPTIME_WARN_DAYS=30

# 通知の頻度制限（同じ警告は X 分以内に再送しない）
NOTIFICATION_COOLDOWN_MIN=60

# ログローテート設定（lib/log.sh が参照。未 source 時は log.sh 側の既定値でフォールバック）
MHK_ROTATE_MAX_BYTES=5242880           # ローテート上限サイズ (5MB)。これ以上で世代退避
MHK_ROTATE_KEEP_GENERATIONS=3          # 保持する世代数（.1〜.3、.4 以降は削除）
MHK_ROTATE_EXTS="log out err"          # ローテート対象拡張子（スペース区切り）
MHK_LOCK_TIMEOUT_SEC=5                 # ロック取得のリトライ上限秒
