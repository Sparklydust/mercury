//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Checks that a nonisolated double can safely expose a stored or recorded value across tasks.
/// - Parameter value: A value whose type must conform to `Sendable`.
@_spi(Generated)
public func previewableRequireSendable<Value: Sendable>(_ value: Value) {}

/// Executes a synchronous double invocation while preserving its declared error type.
/// - Parameters:
///   - lock: The lock shared by the double's storage and invocation records.
///   - body: The invocation to execute while holding the lock.
/// - Throws: The error thrown by `body`.
@_spi(Generated)
public func previewableWithLock<Value, Failure: Error>(
  _ lock: NSRecursiveLock,
  _ body: () throws(Failure) -> Value
) throws(Failure) -> Value {
  lock.lock()
  defer { lock.unlock() }
  return try body()
}
