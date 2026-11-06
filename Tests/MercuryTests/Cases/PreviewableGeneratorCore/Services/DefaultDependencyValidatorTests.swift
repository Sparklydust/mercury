//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct DefaultDependencyValidatorTests {

  @Test(arguments: [
    "subscript(index: Int) -> any NodeProtocol { get }",
    "subscript(index: Int) -> any NodeProtocol { get set }",
    "subscript(index: Int) -> any NodeProtocol { get async }"
  ])
  func dependencies_subscriptConstructsItsOwnDouble_diagnosticIsEmitted(_ requirement: String) {
    let source = "@PreviewableDouble protocol NodeProtocol { \(requirement) }"

    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains("recursive default construction: NodeProtocol → NodeProtocol") == true)
  }

  @Test
  func dependencies_subscriptClosesIndirectCycle_diagnosticIsEmitted() {
    let source = """
      typealias Child = any ChildProtocol
      @PreviewableDouble protocol NodeProtocol { subscript(index: Int) -> Child { get } }
      @PreviewableDouble protocol ChildProtocol { var parent: any NodeProtocol { get } }
      """

    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains("recursive default construction") == true)
  }

  @Test(arguments: [
    "subscript(index: Int) -> (any NodeProtocol)? { get }",
    "subscript(index: Int) -> [any NodeProtocol] { get }",
    "subscript(index: Int) -> () -> any NodeProtocol { get }",
    "subscript<Value>(index: Value) -> any NodeProtocol { get }"
  ])
  func dependencies_subscriptDefaultIsDeferred_generationSucceeds(_ requirement: String) throws {
    let source = "@PreviewableDouble protocol NodeProtocol { \(requirement) }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains("final class NodeDouble"))
  }

  @Test(arguments: [
    "static func make() -> any FactoryProtocol",
    "static var shared: any FactoryProtocol { get }",
    "static subscript(index: Int) -> any FactoryProtocol { get }"
  ])
  func dependencies_staticDefaultConstructsItsOwnDouble_generationSucceeds(_ requirement: String) throws {
    let source = "@PreviewableDouble protocol FactoryProtocol: Sendable { \(requirement) }"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains("private final class _PreviewableStaticState"))
  }

  @Test
  func dependencies_staticDefaultLeadsBackThroughInstance_generationSucceeds() throws {
    let source = """
      protocol FactoryBase: Sendable { static func make() -> any NodeProtocol }
      @PreviewableDouble protocol FactoryProtocol: FactoryBase {}
      @PreviewableDouble protocol NodeProtocol: Sendable { var factory: any FactoryProtocol { get } }
      """

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains("final class FactoryDouble"))
  }
}
