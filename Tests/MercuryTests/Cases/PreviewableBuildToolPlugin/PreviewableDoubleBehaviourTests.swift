//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Testing

@Suite
struct PreviewableDoubleBehaviourTests {

  private struct SampleError: Error {}

  // MARK: - Stubbing
  @Test
  func double_stubIsAssigned_requirementReturnsStub() {
    let double = CatalogueServiceDouble()

    double.titleStub = "Portfolio"
    double.tagsStub = ["equity", "bond"]
    double.stateStub = .loading

    let result = double.title == "Portfolio"
    && double.tags == ["equity", "bond"]
    && double.state == .loading

    #expect(result, "Assigning a stub must change what the requirement returns.")
  }

  @Test
  func double_requirementIsSettable_writeReachesStub() {
    let double = CatalogueServiceDouble()

    double.count = 42

    #expect(double.countStub == 42, "A settable requirement must write through to its stub.")
  }

  @Test
  func double_requirementIsInherited_stubIsGenerated() {
    let double = CatalogueServiceDouble()
    let identifier = UUID()

    double.identifierStub = identifier

    #expect(
      double.identifier == identifier,
      "A requirement inherited from a base protocol must be stubbable on the derived double."
    )
  }

  // MARK: - Spying
  @Test
  func double_methodIsCalled_invocationIsRecorded() async throws {
    let double = CatalogueServiceDouble()
    double.loadStub = ["first"]

    let loaded = try await double.load(page: 7)
    double.reset()

    let result = loaded == ["first"]
    && double.calledMethods == ["load(page:)", "reset()"]
    && double.passedParameters["load(page:)"]?.first?.first as? Int == 7

    #expect(result, "Calls must be recorded with their arguments, including inherited requirements.")
  }

  @Test
  func double_methodIsCalledTwice_everyInvocationIsRecorded() async throws {
    let double = CatalogueServiceDouble()

    _ = try await double.load(page: 1)
    _ = try await double.load(page: 2)

    let recorded = double.passedParameters["load(page:)"]
    let result = recorded?.count == 2
    && recorded?.first?.first as? Int == 1
    && recorded?.last?.first as? Int == 2

    #expect(result, "Each invocation must keep its own arguments rather than overwrite the previous ones.")
  }

  @Test
  func double_errorStubIsAssigned_methodThrows() async {
    let double = CatalogueServiceDouble()
    double.loadErrorStub = SampleError()

    await #expect(throws: SampleError.self) {
      _ = try await double.load(page: 1)
    }
  }

  @Test
  func double_errorsStubIsAssigned_onlyTheQueuedCallsThrow() async throws {
    let double = CatalogueServiceDouble()
    double.loadErrorsStub = [SampleError(), SampleError()]

    await #expect(throws: SampleError.self) { _ = try await double.load(page: 1) }
    await #expect(throws: SampleError.self) { _ = try await double.load(page: 2) }
    let recovered = try await double.load(page: 3)

    #expect(
      recovered == double.loadStub,
      "A queued error must be consumed per call, so a retrying caller can eventually succeed."
    )
  }

  @Test
  func accessor_stubIsAssignedThroughIt_theInjectedDoubleSeesIt() {
    publicServiceDouble.nameStub = "Markets"

    let injected: any PublicServiceProtocol = publicServiceDouble

    #expect(
      injected.name == "Markets",
      "A preview must configure stubs through the accessor it injects, or it cannot arrange anything."
    )
  }

  @Test
  func double_protocolRequiresInitializer_witnessIsGeneratedAndRecorded() {
    let double = FactoryDouble(name: "feed")

    #expect(
      double.calledMethods == ["init(name:)"]
      && double.passedParameters["init(name:)"]?.first?.first as? String == "feed",
      "An initializer requirement must be witnessed, and recorded like every other requirement."
    )
  }

  @Test
  func double_methodTakesClosure_callIsRecordedWithoutCapturingIt() {
    let double = CatalogueServiceDouble()

    double.observe(handler: { _ in }, token: "abc")

    let result = double.calledMethods == ["observe(handler:token:)"]
    && double.passedParameters["observe(handler:token:)"]?.count == 1
    && double.passedParameters["observe(handler:token:)"]?.first?.count == 1
    && double.passedParameters["observe(handler:token:)"]?.first?.first as? String == "abc"

    #expect(result, "A non-escaping closure argument must be skipped, not stored.")
  }

  // MARK: - Composite defaults
  @Test
  func double_requirementIsComposite_defaultIsUsable() {
    let double = CompositionServiceDouble()

    double.onChange()
    let result = double.transform(1).isEmpty
    && double.coordinate == (0, 0)
    && double.delegate is IdentifiableServiceDouble
    && double.owned.owner.isEmpty == false

    #expect(result, "Closures, tuples, existentials and owned types must have working defaults.")
  }

  // MARK: - Preview accessors
  @Test
  func accessor_isRead_sharedDoubleIsReturned() {
    let first = catalogueServiceDouble
    let second = catalogueServiceDouble

    #expect(
      first === second,
      "The accessor must hand back the one shared preview double."
    )
  }

  @MainActor
  @Test
  func accessor_protocolIsMainActorIsolated_doubleIsUsable() {
    let double = PresentationServiceDouble()
    double.headlineStub = "Markets"

    double.present()

    #expect(
      double.headline == "Markets" && double.calledMethods == ["present()"],
      "A globally isolated protocol must produce a usable double."
    )
  }
}
