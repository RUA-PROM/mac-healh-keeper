// Mac Health Keeper - テスト用 ShellRunner スタブ（共有）
//
// 呼び出した executable/args を記録し、設定した戻り値を順次返す。
// JobController/ShellRunner の CQRS・副作用なし検証（UC1-S2 / UC2-S1）に使う。
// 実プロセスは起動しない（決定的）。

import Foundation
@testable import MacHealthKit

final class SpyShellRunner: ShellRunner {
    struct Call: Equatable {
        let executable: String
        let args: [String]
    }

    private(set) var calls: [Call] = []
    private var stubbed: [String]
    private var index = 0
    private let defaultReturn: String

    /// すべての run 呼び出しに同じ戻り値列を順次返す（足りなくなったら defaultReturn）。
    init(stubbed: [String] = [], defaultReturn: String = "") {
        self.stubbed = stubbed
        self.defaultReturn = defaultReturn
    }

    /// 03 §2.5.4 の `stubbedSequence:` 別名（同義）。
    convenience init(stubbedSequence: [String]) {
        self.init(stubbed: stubbedSequence)
    }

    @discardableResult
    func run(_ executable: String, _ args: [String]) -> String {
        calls.append(Call(executable: executable, args: args))
        if index < stubbed.count {
            let v = stubbed[index]
            index += 1
            return v
        }
        return defaultReturn
    }
}
