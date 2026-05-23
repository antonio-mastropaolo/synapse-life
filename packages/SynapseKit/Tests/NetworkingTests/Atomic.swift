import Foundation

/// Lock-backed counters/strings used by URLProtocol-stubbed tests where
/// the request handler runs on an arbitrary URLSession queue. The locks
/// keep these `Sendable` for Swift 6 strict-concurrency without forcing
/// the closures onto `@MainActor`.
final class AtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var n: Int = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}

final class AtomicString: @unchecked Sendable {
    private let lock = NSLock()
    private var s: String = ""
    var value: String { lock.lock(); defer { lock.unlock() }; return s }
    func set(_ v: String) { lock.lock(); defer { lock.unlock() }; s = v }
}
