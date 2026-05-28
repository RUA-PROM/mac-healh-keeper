// Mac Health Keeper - MetricsParser（Domain・純粋パース）
//
// 現 src/MacHealth.swift gatherMetrics() L119-153 の「シェル出力テキスト/数値 → メトリクス値」
// の算出（trim・丸め・単位・フォールバック）を純粋関数群として切り出したもの。
// 丸め・単位・フォールバックは現状の gatherMetrics と完全一致させる。
// 外部コマンドに依存せず、入力はすべて引数で受ける（テスト対象）。AppKit 非依存。

import Foundation

public struct MetricsParser {

    public init() {}

    /// uptime の sed 抽出後テキスト → 負荷平均文字列。
    /// 現 L119-121: trim 後、空なら "—"。
    public func parseLoadAvg(_ text: String) -> String {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? "—" : v
    }

    /// swapusage の sed 抽出後テキスト → スワップ使用文字列。
    /// 現 L123-125: trim 後、空なら "—"。
    public func parseSwapUsed(_ text: String) -> String {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? "—" : v
    }

    /// memory_pressure awk 抽出後テキスト → 空きメモリ % 文字列。
    /// 現 L127-129: trim 後、空なら "—"。
    public func parseMemoryFreePct(_ text: String) -> String {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? "—" : v
    }

    /// boot/now epoch（Int）→ (days, hours)。
    /// 現 L131-137: elapsed = now - boot、days = elapsed/86400、hours = (elapsed%86400)/3600。
    /// boot が Int 変換不可だった場合は呼び出し側が now を渡す（= 0 日 0 時間）想定。
    public func uptimeDaysHours(bootEpoch: Int, nowEpoch: Int) -> (days: Int, hours: Int) {
        let elapsed = nowEpoch - bootEpoch
        let days = elapsed / 86400
        let hours = (elapsed % 86400) / 3600
        return (days, hours)
    }

    /// boot epoch の文字列を受けて (days, hours) を返す。
    /// 現 L132-137: Int 変換不可なら now を使う（= 0 日 0 時間）。
    public func uptimeDaysHours(bootString: String, nowEpoch: Int) -> (days: Int, hours: Int) {
        let bootStr = bootString.trimmingCharacters(in: .whitespacesAndNewlines)
        let boot = Int(bootStr) ?? nowEpoch
        return uptimeDaysHours(bootEpoch: boot, nowEpoch: nowEpoch)
    }

    /// compressor ページ数（文字列）→ "%.1f GB"。
    /// 現 L139-143: pages * 4096 / 1024 / 1024 / 1024 を "%.1f GB"。非数値は 0。
    public func compressedGB(pages: String) -> String {
        let pagesStr = pages.trimmingCharacters(in: .whitespacesAndNewlines)
        let compPages = Double(pagesStr) ?? 0
        let compGB = compPages * 4096 / 1024 / 1024 / 1024
        return String(format: "%.1f GB", compGB)
    }

    /// Docker 行。
    /// 現 L145-153: 起動中は "Docker:         起動中（コンテナ: <count>）"（count 空なら "?"）、
    /// 停止中は "Docker:         停止中"。
    public func dockerLine(running: Bool, containerCount: String) -> String {
        if running {
            let count = containerCount.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Docker:         起動中（コンテナ: \(count.isEmpty ? "?" : count)）"
        } else {
            return "Docker:         停止中"
        }
    }
}
