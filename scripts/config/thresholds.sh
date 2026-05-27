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
