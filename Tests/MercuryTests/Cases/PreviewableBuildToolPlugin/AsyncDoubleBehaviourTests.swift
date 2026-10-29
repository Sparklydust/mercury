//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Testing

struct AsyncDoubleBehaviourTests {

  private let sut = AsyncSpyServiceDouble()

  @Test
  func responses_callsFinishInReverseOrder_eachRetainsItsSnapshot() async throws {
    sut.loadStub = "first"
    sut.loadSpy.pause()
    let expected = ["first", "second"]

    let first = Task { try await sut.load() }
    defer { first.cancel() }
    let firstCall = try await sut.loadSpy.waitForCall()
    sut.loadStub = "second"
    let second = Task { try await sut.load() }
    defer { second.cancel() }
    let secondCall = try await sut.loadSpy.waitForCall()
    secondCall.resume()
    let secondValue = try await second.value
    firstCall.resume()
    let firstValue = try await first.value
    let result = [firstValue, secondValue]

    #expect(result == expected, "Concurrent invocations must retain the responses captured at their own entry.")
  }

  @Test
  func errors_stubChangesWhilePaused_preservesCapturedTypedError() async throws {
    sut.loadErrorStub = .numbered(1)
    sut.loadSpy.pause()
    let expected = ScopedFailure.numbered(1)

    let operation = Task { try await sut.load() }
    defer { operation.cancel() }
    let call = try await sut.loadSpy.waitForCall()
    sut.loadErrorStub = .numbered(2)
    call.resume()

    await #expect(throws: expected) {
      _ = try await operation.value
    }
  }

  @Test
  func errors_queueIsConfigured_consumesQueuedErrorBeforePersistentError() async {
    sut.loadErrorStub = .numbered(2)
    sut.loadErrorsStub = [.numbered(1)]
    let expected = ScopedFailure.numbered(1)

    await #expect(throws: expected) {
      _ = try await sut.load()
    }
  }

  @Test
  func cancellation_typedThrowingMethodIsPaused_preservesConfiguredResponse() async throws {
    sut.loadStub = "configured"
    sut.loadSpy.pause()
    let expected = "configured"

    let operation = Task { try await sut.load() }
    let call = try await sut.loadSpy.waitForCall()
    operation.cancel()
    let result = try await operation.value
    call.resume()

    #expect(result == expected, "Cancellation must release a pause without inventing a new typed error.")
  }

  @Test
  func genericResponse_stubChangesWhilePaused_preservesCapturedValue() async throws {
    sut.makeStub.set(1, for: Int.self)
    sut.makeSpy.pause()
    let expected = 1

    let operation = Task { try await sut.make(Int.self) }
    defer { operation.cancel() }
    let call = try await sut.makeSpy.waitForCall()
    sut.makeStub.set(2, for: Int.self)
    call.resume()
    let result = try await operation.value

    #expect(result == expected, "Generic responses must be captured before the spy can suspend.")
  }

  @Test
  func getter_responseChangesWhilePaused_preservesCapturedValue() async throws {
    sut.statusStub = "original"
    sut.statusSpy.pause()
    let expected = "original"

    let operation = Task { try await sut.status }
    defer { operation.cancel() }
    let call = try await sut.statusSpy.waitForCall()
    sut.statusStub = "changed"
    call.resume()
    let result = try await operation.value

    #expect(result == expected, "Async property getters must use the same snapshot contract as methods.")
  }

  @Test
  func getter_typedErrorIsConfigured_throwsThatError() async {
    sut.statusErrorStub = .numbered(3)
    let expected = ScopedFailure.numbered(3)

    await #expect(throws: expected) {
      _ = try await sut.status
    }
  }

  @Test
  func getter_isInvoked_recordsItsAccessorKey() async throws {
    let expected = ["status.get"]

    _ = try await sut.status
    let result = sut.calledMethods

    #expect(result == expected, "Async getter calls must have a stable recording key.")
  }

  @Test
  func staticMethod_callIsPaused_usesItsScopedSpy() async throws {
    let expected = 42

    let result = try await AsyncSpyServiceDouble.withStaticStubs {
      AsyncSpyServiceDouble.versionStub = 42
      AsyncSpyServiceDouble.versionSpy.pause()
      let operation = Task { await AsyncSpyServiceDouble.version() }
      defer { operation.cancel() }
      let call = try await AsyncSpyServiceDouble.versionSpy.waitForCall()
      call.resume()
      return await operation.value
    }

    #expect(result == expected, "Static spies must use the existing task-scoped static state.")
  }

  @Test
  func staticGetter_valueIsConfigured_returnsScopedResponse() async {
    let expected = 7

    let result = await AsyncSpyServiceDouble.withStaticStubs {
      AsyncSpyServiceDouble.revisionStub = 7
      return await AsyncSpyServiceDouble.revision
    }

    #expect(result == expected, "Async static getters must preserve their scoped configuration.")
  }

  @Test
  func overloads_methodsHaveDifferentArguments_spiesAreIndependent() async {
    let double = AsyncOverloadDouble()
    double.loadIdIntStub = "number"
    double.loadIdStringStub = "text"
    let expected = ["number", "text"]

    let result = [await double.load(id: 1), await double.load(id: "one")]

    #expect(result == expected, "Async overloads must retain independent stubs and spies.")
  }

  @Test
  func rethrows_noErrorIsConfigured_preservesNonthrowingCallSite() async {
    let double = AsyncOverloadDouble()
    double.performStub = "configured"
    let expected = "configured"

    let result = await double.perform { "unused" }

    #expect(result == expected, "Observation must not strengthen a rethrows witness into a throwing method.")
  }

  @Test
  func cancellation_nonthrowingMethodIsPaused_finishesWithoutAnError() async throws {
    sut.refreshSpy.pause()
    let expected = ["refresh()"]

    let operation = Task { await sut.refresh() }
    let call = try await sut.refreshSpy.waitForCall()
    operation.cancel()
    await operation.value
    call.resume()
    let result = sut.calledMethods

    #expect(result == expected, "Cancellation must not strengthen a nonthrowing requirement.")
  }

  @Test
  func legacyResponse_methodIsAsync_preservesNonSendableIdentity() async {
    let double = LegacyAsyncSpyDouble()
    let expected = Session()
    double.loadStub = expected

    let result = await double.load()

    #expect(result === expected, "Legacy async methods must retain their non-Sendable response support.")
  }

  @Test
  @RecordingActor
  func customActor_getterIsAsync_retainsActorLocalResponse() async {
    let double = ActorAsyncSpyDouble()
    let expected = Session()
    double.payloadStub = expected

    let result = await double.payload

    #expect(result === expected, "Async getter controls must preserve custom global-actor isolation.")
  }

  @Test
  func asyncSubscript_responseIsConfigured_usesItsAccessorSpy() async throws {
    let double = AsyncIndexedServiceDouble()
    double.subscriptStub = "configured"
    double.subscriptSpy.pause()
    let expected = "configured"

    let operation = Task { try await double[3] }
    defer { operation.cancel() }
    let call = try await double.subscriptSpy.waitForCall()
    call.resume()
    let result = try await operation.value

    #expect(result == expected, "Async subscript getters must expose independent call controls.")
  }

}
