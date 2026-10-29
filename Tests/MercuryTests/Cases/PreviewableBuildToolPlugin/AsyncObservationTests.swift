//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Testing

@MainActor
struct AsyncObservationTests {

  private let serviceDouble: AsyncObservationDouble
  private let sut: AsyncLoadingModel

  init() {
    serviceDouble = AsyncObservationDouble()
    sut = AsyncLoadingModel(service: serviceDouble)
  }

  @Test
  func observation_requestStarts_isLoadingIsTrue() async {
    var observed: Bool?
    serviceDouble.loadSpy.observe { [weak sut] in observed = sut?.isLoading }
    let expected = true

    await sut.load()
    let result = observed

    #expect(result == expected, "Observation must see loading state before the consumer's defer executes.")
  }

  @Test
  func observation_requestThrows_observerStillRuns() async {
    var observed: Bool?
    serviceDouble.loadErrorStub = ScopedFailure.numbered(1)
    serviceDouble.loadSpy.observe { [weak sut] in observed = sut?.isLoading }
    let expected = true

    await sut.load()
    let result = observed

    #expect(result == expected, "Configured errors must be delivered after observation.")
  }

  @Test
  func observation_observerChangesStub_currentResponseWasAlreadyCaptured() async {
    serviceDouble.loadStub = "original"
    serviceDouble.loadSpy.observe { [weak serviceDouble] in serviceDouble?.loadStub = "changed" }
    let expected = "original"

    await sut.load()
    let result = sut.value

    #expect(result == expected, "Changing a stub inside an observer must affect only subsequent calls.")
  }

  @Test
  func observation_observerChangesStub_nextInvocationUsesUpdatedResponse() async {
    serviceDouble.loadStub = "original"
    serviceDouble.loadSpy.observe { [weak serviceDouble] in serviceDouble?.loadStub = "changed" }
    let expected = "changed"

    await sut.load()
    await sut.load()
    let result = sut.value

    #expect(result == expected, "The next invocation must capture the updated response.")
  }

  @Test
  func isolation_requestIsNotObserved_mainActorIsNotYielded() async {
    var yielded = false
    Task { yielded = true }
    let expected = false

    await sut.load()
    let result = yielded

    #expect(result == expected, "An unobserved request must not let other main-actor work run while it is in flight.")
  }

  @Test
  func getter_responseIsNotSendable_preservesActorLocalIdentity() async {
    let expected = Session()
    serviceDouble.payloadStub = expected

    let result = await serviceDouble.payload

    #expect(result === expected, "Async getters must retain non-Sendable values on their declared actor.")
  }

  @Test
  func pause_requestIsPending_loadingStateRemainsVisible() async throws {
    serviceDouble.loadSpy.pause()
    let expected = true

    let operation = Task { await sut.load() }
    defer { operation.cancel() }
    let call = try await serviceDouble.loadSpy.waitForCall()
    let result = sut.isLoading
    call.resume()
    await operation.value

    #expect(result == expected, "A paused dependency must keep its consumer in the loading state.")
  }

  @Test
  func resume_requestFinishes_loadingStateIsCleared() async throws {
    serviceDouble.loadSpy.pause()
    let expected = false

    let operation = Task { await sut.load() }
    defer { operation.cancel() }
    let call = try await serviceDouble.loadSpy.waitForCall()
    call.resume()
    await operation.value
    let result = sut.isLoading

    #expect(result == expected, "Resuming the invocation must let the consumer run its cleanup.")
  }
}
