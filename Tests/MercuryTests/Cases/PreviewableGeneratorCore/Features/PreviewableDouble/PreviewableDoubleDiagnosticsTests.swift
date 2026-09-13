//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

@Suite
struct PreviewableDoubleDiagnosticsTests {

  @Test(arguments: [
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
      """
      @PreviewableDouble
      protocol ServiceProtocol { func load(); func load(id: Int) }
      """,
      "does not support overloaded requirement 'load'"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol { associatedtype Item; func load() -> Item }
      """,
      "does not support associated types or subscripts"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol { subscript(index: Int) -> String { get } }
      """,
      "does not support associated types or subscripts"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol<Item> { var name: String { get } }
      """,
      "does not support protocols with associated types or generic constraints"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol { static var shared: String { get } }
      """,
      "does not support static property requirements"
    ),
    (
      """
      @PreviewableDouble
      protocol ServiceProtocol { static func make() }
      """,
      "does not support static method requirements"
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
    ),
  ])
  func generator_declarationIsUnsupported_diagnosticNamesTheFix(
    _ source: String,
    _ expected: String
  ) {
    let message = generatorDiagnosticMessage(for: source)

    #expect(
      message?.contains(expected) == true,
      "Expected a diagnostic containing `\(expected)`, got `\(message ?? "no diagnostic")`."
    )
  }
}
