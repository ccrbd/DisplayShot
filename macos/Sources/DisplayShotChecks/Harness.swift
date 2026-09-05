import Foundation

/// Minimal assertion harness so the checks run with the Command Line Tools alone.
struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

enum Checks {
    static var passed = 0
    static var failed = 0

    static func run(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("  ✓ \(name)")
        } catch {
            failed += 1
            print("  ✗ \(name)\n      \(error)")
        }
    }

    static func suite(_ name: String, _ body: () -> Void) {
        print(name)
        body()
    }

    static func finish() -> Never {
        print("\n\(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}

func expect(_ condition: Bool, _ message: String = "expected true", file: StaticString = #filePath, line: UInt = #line) throws {
    if !condition { throw CheckFailure(description: "\(message)  [\(file):\(line)]") }
}

func expectFalse(_ condition: Bool, _ message: String = "expected false", file: StaticString = #filePath, line: UInt = #line) throws {
    try expect(!condition, message, file: file, line: line)
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
    if a != b { throw CheckFailure(description: "\(message.isEmpty ? "" : message + ": ")\(a) != \(b)  [\(file):\(line)]") }
}

func expectEqual(_ a: CGFloat, _ b: CGFloat, accuracy: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws {
    if abs(a - b) > accuracy { throw CheckFailure(description: "\(a) != \(b) ± \(accuracy)  [\(file):\(line)]") }
}

func expectNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "expected values to differ", file: StaticString = #filePath, line: UInt = #line) throws {
    if a == b { throw CheckFailure(description: "\(message)  [\(file):\(line)]") }
}

func expectGreater<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
    if !(a > b) { throw CheckFailure(description: "\(message.isEmpty ? "" : message + ": ")\(a) is not > \(b)  [\(file):\(line)]") }
}

func expectLess<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
    if !(a < b) { throw CheckFailure(description: "\(message.isEmpty ? "" : message + ": ")\(a) is not < \(b)  [\(file):\(line)]") }
}
