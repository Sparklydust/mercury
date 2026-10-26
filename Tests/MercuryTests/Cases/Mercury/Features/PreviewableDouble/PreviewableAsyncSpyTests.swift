//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

@_spi(Generated) import Mercury
import Testing

struct PreviewableAsyncSpyTests {

  private let sut = PreviewableAsyncSpy()

  @Test
  @MainActor
  func observation_callArrives_observerRunsOnItsActor() async {
    var observed: Bool?
    sut.observe { observed = true }
    let expected = true

    await sut.recordCall()
    let result = observed

    #expect(result == expected, "The observer must run before the invocation finishes.")
  }

  @Test
  @MainActor
  func observation_observerIsRemoved_subsequentCallDoesNotNotify() async {
    var observed = false
    sut.observe { observed = true }
    sut.observe(nil)
    let expected = false

    await sut.recordCall()
    let result = observed

    #expect(result == expected, "Removing observation must leave ordinary invocation behavior intact.")
  }

  @Test
  @MainActor
  func observation_callbackConfiguresSpy_mutexIsNotHeld() async {
    sut.observe { [weak sut] in
      sut?.pause()
      sut?.resume()
    }
    let expected = false

    await sut.recordCall()
    let call = try? await sut.waitForCall()
    let result = call?.isPaused

    #expect(result == expected, "Observers must be able to configure their spy without deadlocking.")
  }

  @Test
  func pause_invocationArrives_callRemainsPaused() async throws {
    sut.pause()
    let expected = true

    let operation = Task { await sut.recordCall() }
    defer { operation.cancel() }
    let call = try await sut.waitForCall()
    let result = call.isPaused
    call.resume()
    await operation.value

    #expect(result == expected, "A paused invocation must remain held until explicitly released.")
  }

  @Test
  func resume_callIsResumedTwice_invocationFinishesOnce() async throws {
    sut.pause()
    let expected = false

    let operation = Task { await sut.recordCall() }
    defer { operation.cancel() }
    let call = try await sut.waitForCall()
    call.resume()
    call.resume()
    await operation.value
    let result = call.isPaused

    #expect(result == expected, "Resuming a call more than once must be harmless.")
  }

  @Test
  func pause_previousCallHasFinished_doesNotPauseItRetroactively() async throws {
    await sut.recordCall()
    let expected = false

    sut.pause()
    let call = try await sut.waitForCall()
    let result = call.isPaused

    #expect(result == expected, "Pausing must affect only subsequent invocations.")
  }

  @Test
  func resume_multipleCallsArePaused_releasesEveryCall() async throws {
    sut.pause()
    let expected = [false, false]

    let first = Task { await sut.recordCall() }
    defer { first.cancel() }
    let firstCall = try await sut.waitForCall()
    let second = Task { await sut.recordCall() }
    defer { second.cancel() }
    let secondCall = try await sut.waitForCall()
    sut.resume()
    await first.value
    await second.value
    let result = [firstCall.isPaused, secondCall.isPaused]

    #expect(result == expected, "Resuming the spy must release all pending calls.")
  }

  @Test
  func cancellation_invokingTaskIsCancelled_releasesItsPause() async throws {
    sut.pause()
    let expected = false

    let operation = Task { await sut.recordCall() }
    let call = try await sut.waitForCall()
    operation.cancel()
    await operation.value
    let result = call.isPaused

    #expect(result == expected, "Cancellation must release a suspended invocation.")
  }

  @Test
  func cancellation_taskIsCancelledBeforeInvocation_doesNotSuspend() async throws {
    sut.pause()
    let expected = false

    let operation = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      await sut.recordCall()
    }
    defer { operation.cancel() }
    let call = try await sut.waitForCall()
    await operation.value
    let result = call.isPaused

    #expect(result == expected, "Cancellation before continuation registration must also release the call.")
  }

  @Test
  func waiting_noCallArrives_throwsTimeout() async {
    let expected = PreviewableAsyncSpyError.timedOut

    await #expect(throws: expected) {
      _ = try await sut.waitForCall(timeout: .zero)
    }
  }

  @Test
  func waiting_waitingTaskIsCancelled_throwsCancellation() async {
    let operation = Task { try await sut.waitForCall() }

    operation.cancel()

    await #expect(throws: CancellationError.self) {
      _ = try await operation.value
    }
  }

  @Test
  func waiting_expiredWaiterIsRemoved_nextCallRemainsAvailable() async throws {
    _ = try? await sut.waitForCall(timeout: .zero)
    let expected = false

    await sut.recordCall()
    let call = try await sut.waitForCall()
    let result = call.isPaused

    #expect(result == expected, "An expired waiter must not consume a later invocation.")
  }

  @Test
  func waiting_callsArriveConcurrently_everyHandleIsClaimedOnce() async {
    let expected = 100

    let result = await withTaskGroup(of: PreviewableAsyncCall?.self) { group in
      for _ in 0..<100 {
        group.addTask {
          await sut.recordCall()
          return try? await sut.waitForCall()
        }
      }
      var calls: [PreviewableAsyncCall] = []
      for await call in group {
        guard let call else { continue }
        calls.append(call)
      }
      return Set(calls.map(ObjectIdentifier.init)).count
    }

    #expect(result == expected, "Concurrent waiters must each claim exactly one invocation.")
  }


  @Test
  func waiting_callIsAlreadyQueued_zeroTimeoutStillReturnsIt() async throws {
    await sut.recordCall()
    let expected = false

    let call = try await sut.waitForCall(timeout: .zero)
    let result = call.isPaused

    #expect(result == expected, "An available invocation must not race against a needless timeout task.")
  }


  @Test
  func cancellation_concurrentWaitersAreCancelled_everyWaitFinishes() async {
    let expected = 100

    let result = await withTaskGroup(of: Bool.self) { group in
      for _ in 0..<100 {
        group.addTask {
          do {
            _ = try await sut.waitForCall(timeout: .seconds(3600))
            return false
          } catch { return error is CancellationError }
        }
      }
      group.cancelAll()
      var cancelled = 0
      for await result in group where result { cancelled += 1 }
      return cancelled
    }

    #expect(result == expected, "Cancellation must finish registered and not-yet-registered waiters alike.")
  }

}
