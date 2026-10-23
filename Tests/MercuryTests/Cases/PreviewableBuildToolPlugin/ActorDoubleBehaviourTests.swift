//
// Copyright © 2026 Mercury contributors. MIT licensed.
//
//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Testing

struct ActorDoubleBehaviourTests {

  private var sut: ActorRecordingDouble!

  init() {
    sut = ActorRecordingDouble()
  }

  @Test
  func double_callsUseDifferentActors_everyInvocationIsRecorded() async {
    let expected = 300

    await withTaskGroup(of: Void.self) { group in
      for id in 0..<100 {
        group.addTask { @MainActor in sut.store(RecordedPayload()) }
        group.addTask { @RecordingActor in sut.cache(RecordedPayload()) }
        group.addTask { _ = sut.load(id: id) }
      }
    }
    let result = sut.calledMethods.count

    #expect(result == expected, "Concurrent actor and nonisolated calls must preserve every invocation.")
  }

  @Test
  @MainActor
  func double_requirementUsesMainActor_argumentsStayInItsRecording() {
    let expected = RecordedPayload()

    sut.store(expected)
    let result = sut.mainActorPassedParameters["store(_:)"]?.first?.first as? RecordedPayload

    #expect(result === expected, "The MainActor recording must preserve the argument on MainActor.")
  }

  @Test
  @RecordingActor
  func double_requirementUsesCustomActor_argumentsStayInItsRecording() {
    let expected = RecordedPayload()

    sut.cache(expected)
    let result = sut.recordingActorPassedParameters["cache(_:)"]?.first?.first as? RecordedPayload

    #expect(result === expected, "The custom-actor recording must preserve the argument on its actor.")
  }

  @Test
  @MainActor
  func double_requirementUsesMainActor_sharedRecordingDoesNotExposeItsArguments() {
    sut.store(RecordedPayload())

    let result = sut.passedParameters.isEmpty

    #expect(result, "Non-Sendable arguments must never escape through the nonisolated dictionary.")
  }

  @Test
  func double_protocolUsesMainActor_nonisolatedRequirementsRemainUsable() {
    let double = MixedIsolationDouble()
    let expected = "ready"
    double.loadStub = expected

    let result = double.load(id: 42)

    #expect(result == expected, "Nonisolated witnesses must access synchronized nonisolated stubs.")
  }

  @Test
  func double_protocolUsesMainActor_nonisolatedPropertyRemainsUsable() {
    let double = MixedIsolationDouble()
    let expected = 42

    double.count = expected
    let result = double.count

    #expect(result == expected, "Nonisolated properties must support access outside the protocol's actor.")
  }

  @Test
  @MainActor
  func double_hasMixedIsolation_allCallsAreRecorded() {
    let double = MixedIsolationDouble()
    let expected = ["load(id:)", "store(_:)"]

    _ = double.load(id: 42)
    double.store(RecordedPayload())
    let result = double.calledMethods

    #expect(result == expected, "Calls from both isolation domains must remain visible in order.")
  }
}
