//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

struct PreviewableDoubleGeneratorTests {

  private let source = """
    import Foundation

    enum Mode {
      case ready
      case unavailable
    }

    @PreviewableDouble
    protocol ServiceProtocol {
      var state: Mode { get set }
      func load(id: Int) async throws -> [String]
    }
    """

  @Test(arguments: [
    "/// A test double for `ServiceProtocol`.",
    "/// - Important: Available only in Debug builds.",
    "// Mock values",
    "// Preview value",
    "// Protocol requirements",
    "/// The shared double used by previews.",
    "private(set) var calledMethods: [String] {",
    "private(set) var passedParameters: [String: [[Any?]]] {",
    "stateStub: Mode = Mode.ready",
    "var state: Mode {\n    get { stateStub }\n    set { stateStub = newValue }\n  }",
    "var loadErrorStub: (any Error)?",
    "loadStub: [String] = []",
    "passedParameters[#function, default: []].append([id])",
    "/// The shared `ServiceDouble` for SwiftUI preview dependency injection.",
    "nonisolated var serviceDouble: ServiceDouble",
    "serviceDouble is unavailable outside Debug builds and SwiftUI previews",
  ])
  func generator_protocolIsAnnotated_expectedDoubleMemberIsGenerated(
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "Generated source must contain `\(expected)`."
    )
  }

  @Test(arguments: [
    "servicePreview",
    "func serviceDouble(",
    "func previewable()",
  ])
  func generator_protocolIsAnnotated_obsoleteAPIIsNotGenerated(
    _ forbidden: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      !result.contains(forbidden),
      "Generated source must not contain `\(forbidden)`."
    )
  }

  @Test(arguments: ["MainActor", "Context", "Scope.Context"])
  func generator_requirementsHaveActorIsolation_sendableChecksAreOmitted(_ actorName: String) throws {
    let source = """
      @globalActor actor Context { static let shared = Context() }
      enum Scope { @globalActor actor Context { static let shared = Context() } }
      final class Payload {}
      @PreviewableDouble protocol ServiceProtocol {
        @\(actorName) var payload: Payload? { get set }
        @\(actorName) func store(_ value: Payload) -> Payload?
        @\(actorName) init(value: Payload)
      }
      """

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.contains("previewableRequireSendable(")

    #expect(!result, "Actor-isolated requirements and stubs must accept actor-protected non-Sendable values.")
  }

  @Test(arguments: [
    "<Value: Sendable>() -> Value",
    "<Value>() -> Value where Value: Swift.Sendable",
    "<Value: Codable & Sendable>() -> [Value]",
    "<Value: Transferable>() -> Value?",
    "<Value: ResponseConstraint>() -> Value",
  ])
  func generator_genericResponseIsSendable_responseStoreIsGenerated(_ signature: String) throws {
    let source = """
      protocol Transferable: Sendable {}
      typealias ResponseConstraint = Transferable
      @PreviewableDouble protocol ServiceProtocol { func make\(signature) }
      """
    let expected = "let makeStub = PreviewableResponses()"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Known Sendable constraints must preserve generic response support.")
  }

  @Test(arguments: [
    "identifierStub: UUID = UUID()",
    "var identifier: UUID { identifierStub }",
    "func reset()",
    "nameStub: String = .init()",
  ])
  func generator_protocolInheritsInModuleProtocol_requirementsAreFlattened(
    _ expected: String
  ) throws {
    let sources = [
      """
      @PreviewableDouble
      protocol BaseProtocol {
        var identifier: UUID { get }
        func reset()
      }

      @PreviewableDouble
      protocol ServiceProtocol: BaseProtocol, AnyObject, Sendable {
        var name: String { get }
      }
      """
    ]

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      result.contains(expected),
      "Flattened source must contain `\(expected)`."
    )
  }

  @Test(arguments: [
    ("func map(_ transform: () throws -> Int) rethrows -> Int {", true),
    ("mapErrorStub", false),
  ])
  func generator_requirementRethrows_signatureAndErrorStorageMatchContract(
    _ fragment: String,
    _ expected: Bool
  ) throws {
    let source = """
      @PreviewableDouble
      protocol MappingProtocol {
        func map(_ transform: () throws -> Int) rethrows -> Int
      }
      """

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.contains(fragment)

    #expect(result == expected, "Presence of `\(fragment)` must match the rethrows contract.")
  }

  @Test
  func generator_requirementHasTypedThrows_stubMatchesTheThrownType() throws {
    let sources = [
      """
      enum MappingError: Error { case broken }

      @PreviewableDouble
      protocol MappingProtocol {
        func load() throws(MappingError) -> Int
      }
      """
    ]

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      result.contains("var loadErrorStub: (MappingError)?"),
      "A typed `throws` requirement cannot throw an `any Error`, so the stub must carry the thrown type."
    )
  }

  @Test
  func generator_requirementIsRestated_itIsGeneratedOnce() throws {
    let sources = [
      """
      protocol BaseProtocol { func load() -> Int }

      @PreviewableDouble
      protocol RefinedProtocol: BaseProtocol { func load() -> Int }
      """
    ]

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      result.components(separatedBy: "func load() -> Int {").count == 2,
      "Restating an inherited requirement must generate one witness, not a duplicate or a diagnostic."
    )
  }

  @Test
  func generator_requirementHasTypedThrows_errorQueueMatchesTheThrownType() throws {
    let source = """
      @PreviewableDouble
      protocol MappingProtocol { func load() throws(MappingError) -> Int }
      enum MappingError: Error { case broken }
      """
    let expected = "loadErrorsStub: [MappingError] = []"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "The error queue must use the requirement's declared error type.")
  }

  @Test
  func generator_requirementThrows_errorQueueIsConsumedBeforeTheStoredError() throws {
    let source = """
      @PreviewableDouble
      protocol MappingProtocol { func load() throws(MappingError) -> Int }
      enum MappingError: Error { case broken }
      """

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let queued = try #require(generated.range(of: "if !self.loadErrorsStub.isEmpty"))
    let stored = try #require(generated.range(of: "if let loadErrorStub"))
    let result = queued.lowerBound < stored.lowerBound

    #expect(result, "The queued error check must precede the persistent error check.")
  }

  @Test
  func generator_doubleIsGenerated_declarationIsInsideDebugSection() throws {
    let source = "@PreviewableDouble\nprotocol ServiceProtocol { var name: String { get set } }"

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let debug = try #require(generated.range(of: "#if DEBUG"))
    let release = try #require(generated.range(of: "#else"))
    let declaration = try #require(generated.range(of: "final class ServiceDouble"))
    let result = (debug.upperBound..<release.lowerBound).contains(declaration.lowerBound)

    #expect(result, "The double declaration must appear within the Debug branch.")
  }

  @Test(arguments: [
    "nonisolated var serviceDouble: ServiceDouble",
    "nonisolated var serviceDouble: any ServiceProtocol",
  ])
  func generator_doubleIsGenerated_accessorHasConfigurationSpecificType(_ expected: String) throws {
    let source = "@PreviewableDouble\nprotocol ServiceProtocol { var name: String { get set } }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "The accessor must provide the expected configuration-specific type.")
  }

  @Test
  func generator_protocolRequiresParameterlessInitializer_noDuplicateWitnessIsGenerated() throws {
    let sources = [
      "@PreviewableDouble\nprotocol FeedProtocol { init() }"
    ]

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      result.components(separatedBy: "init()").count == 2,
      "The double already declares `init()`, so witnessing the requirement again would not compile."
    )
  }

  @Test(arguments: ["init() throws", "init?()", "init!()", "init() async throws"])
  func generator_parameterlessRequirementIsWeaker_noDuplicateInitializerIsGenerated(_ initializer: String) throws {
    let source = "@PreviewableDouble protocol Service { \(initializer) }"
    let expected = 1

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.components(separatedBy: "\n").filter { $0.contains("init") && $0.contains("()") }.count

    #expect(result == expected, "The existing nonthrowing, nonfailable initializer must witness the requirement once.")
  }

  @Test(arguments: ["Swift.Sendable", "Swift.AnyObject", "@preconcurrency Swift.Sendable"])
  func generator_markerProtocolIsQualified_doubleIsGenerated(_ marker: String) throws {
    let source = "@PreviewableDouble protocol Service: \(marker) {}"
    let expected = "final class ServiceDouble"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected), "Qualified standard marker protocols must not require module-local declarations.")
  }

  @Test
  func generator_unrelatedQualifiedProtocolSharesMarkerName_requirementsArePreserved() throws {
    let source = """
      enum Domain { protocol Sendable { func load() } }
      @PreviewableDouble protocol Service: Domain.Sendable {}
      """
    let expected = "func load()"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "An unrelated qualified protocol must not be mistaken for a standard marker.")
  }

  @Test
  func generator_publicProtocolHasInternalParent_doubleAccessIsCapped() throws {
    let source = "enum Scope { @PreviewableDouble public protocol Service {} }"
    let expected = "final class ServiceDouble: Scope.Service, @unchecked Sendable {"

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.components(separatedBy: "\n").first { $0.contains("final class ServiceDouble") }

    #expect(result == expected, "A generated top-level double must respect its protocol's effective visibility.")
  }
}
