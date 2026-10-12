import Foundation

// MARK: - Lightweight Test Framework

@MainActor
final class TestSuite {
    static let shared = TestSuite()

    private var passed = 0
    private var failed = 0
    private var failures: [String] = []

    func run(name: String, test: () async throws -> Void) async {
        print("▶ Running \(name)...", terminator: " ")
        fflush(stdout)
        do {
            try await test()
            passed += 1
            print("\u{001B}[32mPASSED\u{001B}[0m")
        } catch {
            failed += 1
            let msg = "\(name) FAILED: \(error.localizedDescription)"
            failures.append(msg)
            print("\u{001B}[31mFAILED\u{001B}[0m")
            print("  ↳ \u{001B}[31m\(error)\u{001B}[0m")
        }
    }

    func report() -> Int32 {
        print("\n================ Test Results ================")
        print("Total: \(passed + failed) | Passed: \u{001B}[32m\(passed)\u{001B}[0m | Failed: \u{001B}[31m\(failed)\u{001B}[0m")
        if !failures.isEmpty {
            print("\nFailures:")
            for f in failures {
                print("  • \(f)")
            }
            return 1
        }
        print("All tests passed successfully! ✅\n")
        return 0
    }
}

struct TestFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func assertTrue(_ condition: Bool, _ message: String = "Expected true, got false", file: StaticString = #file, line: UInt = #line) throws {
    guard condition else {
        throw TestFailure(message: "\(message) at \(file):\(line)")
    }
}

func assertFalse(_ condition: Bool, _ message: String = "Expected false, got true", file: StaticString = #file, line: UInt = #line) throws {
    guard !condition else {
        throw TestFailure(message: "\(message) at \(file):\(line)")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws {
    guard a == b else {
        let extra = message.isEmpty ? "" : " (\(message))"
        throw TestFailure(message: "Expected '\(b)', but got '\(a)'\(extra) at \(file):\(line)")
    }
}

func assertNotNil<T>(_ val: T?, _ message: String = "Expected non-nil value", file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let v = val else {
        throw TestFailure(message: "\(message) at \(file):\(line)")
    }
    return v
}
