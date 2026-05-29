// Mac Health Keeper - MacHealthCheck テストランナー（XCTest 非依存）
//
// issue: 20260529_083530_メトリクス非表示修正 フォロー
//
// XCTest / swift-testing が利用できない環境（macOS Command Line Tools のみ等）でも
// Functional Core の純粋関数群に対する BDD 形式の単体テストを「実行」して回帰検知できるよう、
// Foundation のみで動く最小のアサーションランナーを提供する。
//
// 形式は .agents/TEST_BDD_FORMAT.md に従い、各テストは
//   useCase("〜") { scenario("〜") { given/when/then } }
// の入れ子で表現する。失敗が 1 件でもあれば最終的に exit(1) する（make check の必須経路）。

import Foundation

/// 1 件のアサーション失敗を表す情報。
struct CheckFailure {
    let useCase: String
    let scenario: String
    let message: String
}

/// グローバルなランナー状態。`useCase`/`scenario` ブロックの入れ子で
/// 現在のコンテキストを保持する。
final class CheckRunner {
    static let shared = CheckRunner()

    private(set) var passed: Int = 0
    private(set) var failures: [CheckFailure] = []
    private var currentUseCase: String = ""
    private var currentScenario: String = ""

    private init() {}

    /// ユースケースのまとまり（BDD のテストクラス相当）。
    func useCase(_ name: String, _ body: () -> Void) {
        let prev = currentUseCase
        currentUseCase = name
        print("ユースケース: \(name)")
        body()
        currentUseCase = prev
    }

    /// 1 シナリオ（BDD のテストメソッド相当）。
    func scenario(_ name: String, _ body: () -> Void) {
        let prev = currentScenario
        currentScenario = name
        body()
        currentScenario = prev
    }

    /// 等値アサーション。失敗時に詳細を記録するが処理は続行する。
    func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passed += 1
            print("  ok   - \(currentScenario): \(message)")
        } else {
            failures.append(CheckFailure(useCase: currentUseCase,
                                         scenario: currentScenario,
                                         message: "\(message) (expected '\(expected)', got '\(actual)')"))
            print("  FAIL - \(currentScenario): \(message) (expected '\(expected)', got '\(actual)')")
        }
    }

    /// 真値アサーション。
    func assertTrue(_ actual: Bool, _ message: String) {
        if actual {
            passed += 1
            print("  ok   - \(currentScenario): \(message)")
        } else {
            failures.append(CheckFailure(useCase: currentUseCase,
                                         scenario: currentScenario,
                                         message: "\(message) (expected true, got false)"))
            print("  FAIL - \(currentScenario): \(message) (expected true, got false)")
        }
    }

    /// 偽値アサーション。
    func assertFalse(_ actual: Bool, _ message: String) {
        assertTrue(!actual, message)
    }

    /// 集計と終了コードの決定。
    func finishAndExit() -> Never {
        print("")
        print("MacHealthCheck: \(passed) passed, \(failures.count) failed")
        if !failures.isEmpty {
            print("---- failures ----")
            for f in failures {
                print("  [\(f.useCase) / \(f.scenario)] \(f.message)")
            }
            exit(1)
        }
        exit(0)
    }
}

/// ヘルパ（DSL 風）。
func useCase(_ name: String, _ body: () -> Void) {
    CheckRunner.shared.useCase(name, body)
}

func scenario(_ name: String, _ body: () -> Void) {
    CheckRunner.shared.scenario(name, body)
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    CheckRunner.shared.assertEqual(actual, expected, message)
}

func assertTrue(_ actual: Bool, _ message: String) {
    CheckRunner.shared.assertTrue(actual, message)
}

func assertFalse(_ actual: Bool, _ message: String) {
    CheckRunner.shared.assertFalse(actual, message)
}
