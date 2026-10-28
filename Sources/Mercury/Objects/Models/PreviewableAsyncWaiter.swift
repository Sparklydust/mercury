//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Synchronization

/// Resolves a waiting test once, even when cancellation arrives before continuation registration.
final class PreviewableAsyncWaiter: Sendable {

  private let state = Mutex(PreviewableAsyncWaiterState())

  /// Delivers an outcome if cancellation, timeout, or call arrival has not already claimed this waiter.
  /// - Parameter result: The call or error offered to the waiting task.
  /// - Returns: Whether this outcome won the race to resolve the waiter.
  @discardableResult
  func resolve(_ result: Result<PreviewableAsyncCall, any Error>) -> Bool {
    guard let resolution = claim(result) else { return false }
    resolution.resume()
    return true
  }

  /// Claims an outcome without resuming a continuation while an outer mutex may still be held.
  func claim(_ result: Result<PreviewableAsyncCall, any Error>) -> PreviewableAsyncResolution? {
    state.withLock { state in
      guard state.result == nil else { return nil }
      state.result = result
      let continuation = state.continuation
      state.continuation = nil
      return PreviewableAsyncResolution(result: result, continuation: continuation)
    }
  }

  /// Returns the claimed call, suspending only while no outcome has arrived.
  /// - Throws: The cancellation or timeout error that resolved the waiter.
  func wait() async throws -> PreviewableAsyncCall {
    try await withCheckedThrowingContinuation { continuation in
      let result: Result<PreviewableAsyncCall, any Error>? = state.withLock { state in
        guard let result = state.result else {
          state.continuation = continuation
          return nil
        }
        return result
      }
      guard let result else { return }
      continuation.resume(with: result)
    }
  }
}
