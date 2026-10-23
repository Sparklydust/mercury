//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct PreviewableDoubleDiagnosticsTests {

  @Test(arguments: ["os(iOS)", "DEBUG", "FEATURE_ENABLED"])
  func generator_protocolHasConditionalRequirements_diagnosticNamesUnsupportedBlock(_ condition: String) {
    let source = """
      @PreviewableDouble protocol Service {
        #if \(condition)
        func refresh()
        #endif
      }
      """

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result?.contains("conditional requirements in 'Service'") == true,
      "Conditional witnesses cannot be omitted."
    )
  }

  @Test
  func generator_inheritedProtocolHasConditionalRequirements_diagnosticNamesBaseProtocol() {
    let source = """
      protocol Base {
        #if os(iOS)
        func refresh()
        #endif
      }
      @PreviewableDouble protocol Service: Base {}
      """

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result?.contains("conditional requirements in 'Base'") == true,
      "Inherited conditional requirements must fail."
    )
  }

  @Test(arguments: [
    (
      "typealias ServiceDouble = Int\n@PreviewableDouble protocol Service {}",
      "generated type 'ServiceDouble' conflicts with an existing declaration"
    ),
    (
      "typealias ServiceDouble<Value> = [Value]\n@PreviewableDouble protocol Service {}",
      "generated type 'ServiceDouble' conflicts with an existing declaration"
    ),
    (
      "@PreviewableDouble protocol Service: Sendable { func make<Value>() -> Value }",
      "generic response 'Value' in 'make' requires a Sendable constraint"
    ),
    (
      "@PreviewableDouble protocol Service: Sendable { func make<Value: Codable>() -> [Value] }",
      "generic response 'Value' in 'make' requires a Sendable constraint"
    ),
    (
      """
      enum Domain { protocol Sendable {} }
      @PreviewableDouble protocol Service: Swift.Sendable { func make<Value: Domain.Sendable>() -> Value }
      """,
      "generic response 'Value' in 'make' requires a Sendable constraint"
    ),
    (
      """
      protocol BaseProtocol { func reset() }
      @PreviewableDouble
      protocol ServiceProtocol: Codable { var name: String { get } }
      """,
      "cannot read the requirements of 'Codable'"
    ),
    (
      """
      @PreviewableDouble
      protocol Service { var a: String { get } }
      @PreviewableDouble
      protocol ServiceProtocol { var b: String { get } }
      """,
      "both generate 'ServiceDouble'"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol { func copy() -> Self }
      """,
      "does not support 'Self' in requirement 'copy'"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol { var twin: Self { get } }
      """,
      "does not support 'Self' in requirement 'twin'"
    ),
    (
      "@PreviewableDouble protocol Service<Item> { var name: String { get } }",
      "primary associated types must have associatedtype declarations"
    ),
    (
      "typealias A = B\ntypealias B = A\n@PreviewableDouble protocol Service { func load(_ value: A) }",
      "cyclic type alias"
    ),
    (
      "protocol Base { var value: Int { get } }\n"
        + "@PreviewableDouble protocol Service: Base { var value: String { get } }",
      "property 'value' has incompatible requirements"
    ),
    (
      "protocol Base { @MainActor func load() }\n@PreviewableDouble protocol Service: Base { func load() }",
      "requirement 'load' has incompatible isolation"
    ),
    (
      "@PreviewableDouble protocol Service where Item == Int, Item == String { associatedtype Item }",
      "incompatible same-type bindings"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol { func load<Failure: Error>() throws(Failure) }
      """,
      "does not support a generic thrown error type"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol { func log(messages: String...) }
      """,
      "does not support variadic parameters"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol { func load(_: Int) }
      """,
      "requires a named local parameter"
    )
  ])
  func generator_declarationIsUnsupported_diagnosticNamesTheFix(
    _ source: String,
    _ expected: String
  ) {
    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result?.contains(expected) == true,
      "Expected a diagnostic containing `\(expected)`, got `\(result ?? "no diagnostic")`."
    )
  }
}
