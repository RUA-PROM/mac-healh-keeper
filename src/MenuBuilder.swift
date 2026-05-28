// Mac Health Keeper - MenuBuilder（UI・AppKit 変換）
//
// MenuModel が生成した [MenuItemSpec] を NSMenu/NSMenuItem に変換する薄い AppKit 部。
// MenuAction を #selector にマッピングし、representedObject・target・toolTip・keyEquivalent を
// 現状（現 rebuildMenu L210-365）どおり設定する。NSMenu 生成は AppKit 実依存のため XCTest 対象外
// （02 §6.1）。項目データの正しさは MenuModelTests、変換の正しさはメニュー目視（T10）で確認する。

// 注: swiftc ビルドでは src/ と Sources/MacHealthKit/ を 1 モジュールとしてまとめてコンパイルするため
// import MacHealthKit は不要（型は同一モジュール内で解決される）。
import Cocoa

struct MenuBuilder {

    /// [MenuItemSpec] を NSMenu に変換する。target は @objc アクションを受ける AppDelegate。
    func makeMenu(_ specs: [MenuItemSpec], target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for spec in specs {
            switch spec.kind {
            case .separator:
                menu.addItem(.separator())

            case .disabled:
                let item = NSMenuItem(title: spec.title, action: nil, keyEquivalent: spec.keyEquivalent)
                item.isEnabled = false
                menu.addItem(item)

            case .item:
                let selector = spec.action.flatMap { Self.selector(for: $0) }
                let item = NSMenuItem(title: spec.title, action: selector, keyEquivalent: spec.keyEquivalent)
                item.isEnabled = spec.isEnabled
                if let job = spec.representedJob {
                    item.representedObject = job
                }
                if let tip = spec.tooltip {
                    item.toptip(tip)
                }
                // terminate は responder chain（NSApplication.terminate(_:)）へ。
                // それ以外は AppDelegate を target にする（現状どおり）。
                if spec.action != .terminate {
                    item.target = target
                }
                menu.addItem(item)
            }
        }
        return menu
    }

    /// MenuAction → Selector のマッピング（現 rebuildMenu の #selector と 1 対 1）。
    static func selector(for action: MenuAction) -> Selector {
        switch action {
        case .refreshNow:           return #selector(AppDelegate.refreshNow)
        case .quickAppRefresh:      return #selector(AppDelegate.quickAppRefresh)
        case .quickPurge:           return #selector(AppDelegate.quickPurge)
        case .quickMemoryPressure:  return #selector(AppDelegate.quickMemoryPressure)
        case .quickDockerQuit:      return #selector(AppDelegate.quickDockerQuit)
        case .toggleJob:            return #selector(AppDelegate.toggleJob(_:))
        case .runJob:               return #selector(AppDelegate.runJob(_:))
        case .openEventsLog:        return #selector(AppDelegate.openEventsLog)
        case .openMonitorLog:       return #selector(AppDelegate.openMonitorLog)
        case .testNotification:     return #selector(AppDelegate.testNotification)
        case .pauseAllJobs:         return #selector(AppDelegate.pauseAllJobs)
        case .resumeAllJobs:        return #selector(AppDelegate.resumeAllJobs)
        case .showMetricsHelp:      return #selector(AppDelegate.showMetricsHelp)
        case .showAbout:            return #selector(AppDelegate.showAbout)
        case .terminate:            return #selector(NSApplication.terminate(_:))
        }
    }
}

// NSMenuItem にツールチップヘルパ（現 src/MacHealth.swift L616-621 を移設）。
extension NSMenuItem {
    func toptip(_ text: String) {
        self.toolTip = text
    }
}
