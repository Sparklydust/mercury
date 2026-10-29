//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Testing

struct PreviewableDoubleBehaviourTests {

  private var sut: CatalogueServiceDouble

  init() {
    sut = CatalogueServiceDouble()
  }

  @Test
  func double_titleStubIsAssigned_requirementReturnsStub() {
    sut.titleStub = "Portfolio"
    let expected = "Portfolio"

    let result = sut.title

    #expect(result == expected, "The title must equal its configured stub.")
  }

  @Test
  func double_tagsStubIsAssigned_requirementReturnsStub() {
    sut.tagsStub = ["equity", "bond"]
    let expected = ["equity", "bond"]

    let result = sut.tags

    #expect(result == expected, "The tags must equal their configured stub.")
  }

  @Test
  func double_stateStubIsAssigned_requirementReturnsStub() {
    sut.stateStub = LoadingState.loading
    let expected = LoadingState.loading

    let result = sut.state

    #expect(result == expected, "The state must equal its configured stub.")
  }

  @Test
  func double_requirementIsSettable_writeReachesStub() {
    let expected = 42

    sut.count = expected
    let result = sut.countStub

    #expect(result == expected, "A settable requirement must update its stub.")
  }

  @Test
  func double_requirementIsInherited_stubIsGenerated() {
    let expected = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
    sut.identifierStub = expected

    let result = sut.identifier

    #expect(result == expected, "An inherited requirement must return its configured stub.")
  }

  @Test
  func double_methodIsCalled_configuredResponseIsReturned() async throws {
    sut.loadStub = ["first"]
    let expected = ["first"]

    let result = try await sut.load(page: 7)

    #expect(result == expected, "The method must return its configured response.")
  }

  @Test
  func double_methodsAreCalled_invocationsAreRecordedInOrder() async throws {
    let expected = ["load(page:)", "reset()"]

    _ = try await sut.load(page: 7)
    sut.reset()
    let result = sut.calledMethods

    #expect(result == expected, "Invocation records must preserve call order, including inherited methods.")
  }

  @Test
  func double_methodIsCalled_argumentIsRecorded() async throws {
    let expected = 7

    _ = try await sut.load(page: expected)
    let result = sut.passedParameters["load(page:)"]?.first?.first as? Int

    #expect(result == expected, "The invocation must record the supplied argument.")
  }

  @Test
  func double_methodIsCalledTwice_everyArgumentIsRecorded() async throws {
    let expected = [1, 2]

    for page in expected {
      _ = try await sut.load(page: page)
    }
    let result = sut.passedParameters["load(page:)"]?.compactMap { $0.first as? Int }

    #expect(result == expected, "Repeated calls must retain each argument in order.")
  }

  @Test
  func double_errorStubIsAssigned_methodThrows() async {
    sut.loadErrorStub = ConstructionError.invalid
    let expected = ConstructionError.invalid

    await #expect(throws: expected) {
      _ = try await sut.load(page: 1)
    }
  }

  @Test
  func double_errorsStubIsAssigned_queuedFailuresAreFollowedBySuccess() async throws {
    sut.loadErrorsStub = [ConstructionError.invalid, ConstructionError.invalid]
    let expected: [ConstructionError?] = [.invalid, .invalid, nil]

    var result: [ConstructionError?] = []
    for page in 1...3 {
      do {
        _ = try await sut.load(page: page)
        result.append(nil)
      } catch let error as ConstructionError {
        result.append(error)
      }
    }

    #expect(result == expected, "Each queued error must be consumed once before a later call succeeds.")
  }

  @Test
  func double_publicProtocolIsInjected_configuredStubIsReturned() {
    let serviceDouble = PublicServiceDouble()
    serviceDouble.nameStub = "Markets"
    let expected = "Markets"

    let injected: any PublicServiceProtocol = serviceDouble
    let result = injected.name

    #expect(result == expected, "Protocol injection must retain the configured public double.")
  }

  @Test
  func double_protocolRequiresInitializer_invocationIsRecorded() {
    let expected = ["init(name:)"]
    let sut = FactoryDouble(name: "feed")
    let result = sut.calledMethods

    #expect(result == expected, "The initializer witness must record its invocation.")
  }

  @Test
  func double_protocolRequiresInitializer_argumentIsRecorded() {
    let expected = "feed"
    let sut = FactoryDouble(name: "feed")
    let result = sut.passedParameters["init(name:)"]?.first?.first as? String

    #expect(result == expected, "The initializer witness must record its argument.")
  }

  @Test
  func double_methodTakesClosure_onlyNonFunctionArgumentsAreRecorded() {
    let expected = ["abc"]

    sut.observe(handler: { _ in }, token: "abc")
    let result = sut.passedParameters["observe(handler:token:)"]?.first?.map { $0 as? String }

    #expect(result == expected, "The argument record must exclude the function argument.")
  }

  @Test
  func double_methodTakesClosure_invocationIsRecorded() {
    let expected = ["observe(handler:token:)"]

    sut.observe(handler: { _ in }, token: "abc")
    let result = sut.calledMethods

    #expect(result == expected, "A method with a function argument must still record its invocation.")
  }

  @Test
  func double_voidClosureHasDefault_invocationCompletes() {
    let sut = CompositionServiceDouble()

    #expect(throws: Never.self) {
      sut.onChange()
    }
  }

  @Test
  func double_closureReturnsString_defaultIsEmpty() {
    let sut = CompositionServiceDouble()

    let result = sut.transform(1)

    #expect(result.isEmpty, "A default transform must return an empty string.")
  }

  @Test
  func double_requirementIsTuple_elementsDefaultToZero() {
    let sut = CompositionServiceDouble()

    let result = sut.coordinate

    #expect(result == (0, 0), "The tuple default must contain zero-valued elements.")
  }

  @Test
  func double_requirementIsExistential_defaultIsConformingDouble() {
    let sut = CompositionServiceDouble()

    let result = sut.delegate

    #expect(result is IdentifiableServiceDouble, "The existential default must be a conforming generated double.")
  }

  @Test
  func double_requirementIsOwnedType_defaultIsPopulatedFake() {
    let sut = CompositionServiceDouble()

    let result = sut.owned.owner

    #expect(!result.isEmpty, "An owned type must receive a populated fake.")
  }

  @Test
  func accessor_isRead_sharedDoubleIsReturned() {
    let expected = CatalogueServiceDouble.preview

    let result = catalogueServiceDouble

    #expect(result === expected, "The accessor must return the shared preview instance.")
  }

  @Test
  func accessor_publicProtocolIsRead_freshDoubleIsReturned() {
    let expected = PublicServiceDouble.preview

    let result = publicServiceDouble

    #expect(result !== expected, "A non-Sendable accessor must return a fresh preview instance.")
  }

  @MainActor
  @Test
  func double_protocolIsMainActorIsolated_stubIsReturned() {
    let sut = PresentationServiceDouble()
    let expected = "Markets"
    sut.headlineStub = expected

    let result = sut.headline

    #expect(result == expected, "The isolated requirement must return its stub.")
  }

  @MainActor
  @Test
  func double_protocolIsMainActorIsolated_invocationIsRecorded() {
    let sut = PresentationServiceDouble()
    let expected = ["present()"]

    sut.present()
    let result = sut.calledMethods

    #expect(result == expected, "The isolated double must record its method calls.")
  }
}
