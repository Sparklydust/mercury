//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

@Suite
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
}
