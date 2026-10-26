//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Synchronization

/// Observes async invocations and optionally holds their captured responses until resumed.
/// Each generated async member owns a separate spy. Observation and task suspension run outside its mutex.
public final class PreviewableAsyncSpy: Sendable {

  private let state = Mutex(PreviewableAsyncSpyState())

  /// Creates a spy that lets invocations finish immediately.
  public init() {}

  /// Replaces the observer invoked before each response or configured error is delivered.
  /// Captures are retained until the observer is replaced or removed. Use weak captures for owners holding this spy.
  /// - Parameter observer: A nonthrowing closure that inherits its creation context's actor; `nil` removes observation.
  public func observe(@_inheritActorContext _ observer: PreviewableAsyncObserver?) {
    state.withLock { $0.observer = observer }
  }

  /// Holds subsequent invocations until their call handles are resumed or their tasks are cancelled.
  public func pause() {
    state.withLock { $0.paused = true }
  }

  /// Releases all current pauses and lets subsequent invocations finish immediately.
  public func resume() {
    let calls = state.withLock { state in
      state.paused = false
      return state.activeCalls
    }
    for call in calls { call.resume() }
  }

  /// Consumes the next unclaimed invocation in arrival order, including calls that have already finished.
  /// - Parameter timeout: The maximum wait when no invocation is available; defaults to five seconds.
  /// - Throws: `PreviewableAsyncSpyError.timedOut` on expiry, or `CancellationError` if this wait is cancelled.
  public func waitForCall(timeout: Duration = .seconds(5)) async throws -> PreviewableAsyncCall {
    try Task.checkCancellation()
    guard let call = nextCall() else { return try await waitForFutureCall(timeout: timeout) }
    return call
  }

  /// Records entry and awaits observation and any configured pause before delivering the caller's snapshot.
  /// Cancellation releases the pause without replacing the method's declared response or error.
  @_spi(Generated)
  public func recordCall() async {
    let entry = state.withLock { state in
      let call = PreviewableAsyncCall(paused: state.paused)
      state.activeCalls.append(call)
      let resolution = deliver(call, to: &state)
      return (call: call, observer: state.observer, resolution: resolution)
    }
    entry.resolution?.resume()
    await withTaskCancellationHandler {
      await entry.observer?()
      await entry.call.wait()
    } onCancel: {
      entry.call.resume()
    }
    state.withLock { $0.activeCalls.removeAll { $0 === entry.call } }
  }
}

private extension PreviewableAsyncSpy {

  func nextCall() -> PreviewableAsyncCall? {
    state.withLock { state in
      guard !state.calls.isEmpty else { return nil }
      return state.calls.removeFirst()
    }
  }

  func waitForFutureCall(timeout: Duration) async throws -> PreviewableAsyncCall {
    let waiter = PreviewableAsyncWaiter()
    let deadline = timeoutTask(for: waiter, after: timeout)
    defer {
      deadline.cancel()
      remove(waiter)
    }
    return try await withTaskCancellationHandler {
      register(waiter)
      return try await waiter.wait()
    } onCancel: {
      waiter.resolve(.failure(CancellationError()))
      self.remove(waiter)
    }
  }

  func timeoutTask(for waiter: PreviewableAsyncWaiter, after timeout: Duration) -> Task<Void, Never> {
    Task {
      do { try await Task.sleep(for: timeout) } catch { return }
      waiter.resolve(.failure(PreviewableAsyncSpyError.timedOut))
      remove(waiter)
    }
  }

  func register(_ waiter: PreviewableAsyncWaiter) {
    let resolution: PreviewableAsyncResolution? = state.withLock { state in
      guard let call = state.calls.first else {
        state.waiters.append(waiter)
        return nil
      }
      guard let resolution = waiter.claim(.success(call)) else { return nil }
      state.calls.removeFirst()
      return resolution
    }
    resolution?.resume()
  }

  /// Claims calls and waiters atomically so cancelled waiters cannot consume or reorder an invocation.
  func deliver(_ call: PreviewableAsyncCall, to state: inout PreviewableAsyncSpyState) -> PreviewableAsyncResolution? {
    while !state.waiters.isEmpty {
      let waiter = state.waiters.removeFirst()
      guard let resolution = waiter.claim(.success(call)) else { continue }
      return resolution
    }
    state.calls.append(call)
    return nil
  }

  func remove(_ waiter: PreviewableAsyncWaiter) {
    state.withLock { $0.waiters.removeAll { $0 === waiter } }
  }
}
