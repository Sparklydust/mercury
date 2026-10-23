//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct SendabilityGeneratorTests {

  @Test(arguments: [
    "@PreviewableDouble protocol Legacy {}",
    "protocol Base {}\n@PreviewableDouble protocol Legacy: Base {}"
  ])
  func generator_protocolIsNotSendable_doubleDoesNotAddConformance(_ source: String) throws {
    let expected = "final class LegacyDouble: Legacy {"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "A legacy double must preserve the protocol's contract."
    )
  }

  @Test(arguments: [
    "@PreviewableDouble protocol Service: Sendable {}",
    "protocol Base: Sendable {}\n@PreviewableDouble protocol Service: Base {}",
    "@MainActor @PreviewableDouble protocol Service {}"
  ])
  func generator_protocolIsSendable_doubleRetainsConformance(_ source: String) throws {
    let expected = "final class ServiceDouble: Service, @unchecked Sendable {"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected))
  }

  @Test
  func generator_protocolIsNotSendable_previewCreatesFreshNonisolatedInstance() throws {
    let source = "@PreviewableDouble protocol Legacy {}"
    let expected = "nonisolated static var preview: LegacyDouble { LegacyDouble() }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected))
  }

  @Test
  func generator_legacyAssociatedResponse_canBeNonSendable() throws {
    let source = "@PreviewableDouble protocol Legacy { associatedtype Value; func load() -> Value }"
    let expected = "_PreviewableValue: Sendable"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      !result.contains(expected),
      "Legacy associated types must not gain concurrency constraints."
    )
  }

  @Test
  func generator_legacyGenericResponse_usesLocalStorage() throws {
    let source = "@PreviewableDouble protocol Legacy { func load<Value>(_ type: Value.Type) -> Value }"
    let expected = "PreviewableLocalResponses()"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Legacy generic responses must accept non-Sendable values.")
  }
}
