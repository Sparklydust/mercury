//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Synchronization

/// Controls the pause of one async invocation independently of other calls.
/// Resuming is idempotent. Cancelling the invoking task also releases its pause.
public final class PreviewableAsyncCall: Sendable {

  private let state: Mutex<PreviewableAsyncCallState>

  /// Whether this invocation has an unreleased pause, including while its observer executes.
  public var isPaused: Bool { state.withLock { !$0.resumed } }

  /// Creates a handle whose pause can be released before or after continuation registration.
  /// - Parameter paused: Whether the invoking task must wait for a release.
  init(paused: Bool) {
    state = Mutex(PreviewableAsyncCallState(resumed: !paused))
  }

  /// Releases this invocation so it can deliver its captured response or error.
  public func resume() {
    let continuation = state.withLock { state in
      state.resumed = true
      let continuation = state.continuation
      state.continuation = nil
      return continuation
    }
    continuation?.resume()
  }

  /// Suspends until the pause is released, returning immediately if it was already released.
  func wait() async {
    await withCheckedContinuation { suspend($0) }
  }

  private func suspend(_ continuation: CheckedContinuation<Void, Never>) {
    let resumed = state.withLock { state in
      guard !state.resumed else { return true }
      state.continuation = continuation
      return false
    }
    guard resumed else { return }
    continuation.resume()
  }
}
