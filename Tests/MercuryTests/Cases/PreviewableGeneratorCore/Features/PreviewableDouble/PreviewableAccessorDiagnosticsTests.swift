//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

struct PreviewableAccessorDiagnosticsTests {

  @Test(arguments: [
    "let serviceDouble = 1",
    "let (serviceDouble, other) = (1, 2)",
    "let `serviceDouble` = 1",
    "private let serviceDouble = 1",
    "func serviceDouble() -> Int { 1 }",
    "struct serviceDouble {}",
    "@PreviewableDouble protocol service {}",
  ])
  func generator_accessorNameAlreadyExists_diagnosticNamesConflict(_ declaration: String) {
    let source = declaration + "\n@PreviewableDouble protocol Service {}"

    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains("generated name 'serviceDouble' conflicts") == true, "Conflicts must fail during generation.")
  }

  @Test(arguments: [
    "struct Scope { let serviceDouble = 1 }",
    "func configure() { let serviceDouble = 1 }",
    "func serviceDouble(_ value: Int) -> Int { value }",
  ])
  func generator_nameCanCoexistWithAccessor_generationSucceeds(_ declaration: String) throws {
    let source = declaration + "\n@PreviewableDouble protocol Service {}"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains("var serviceDouble: ServiceDouble"), "Local names and callable overloads must remain valid.")
  }

  @Test
  func generator_genericDoubleHasNoAccessor_globalNameRemainsAvailable() throws {
    let source = """
      let serviceDouble = 1
      @PreviewableDouble protocol Service { associatedtype Value; func load() -> Value }
      """

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(!result.contains("var serviceDouble:"), "Generic doubles must not reserve an accessor they do not emit.")
  }
}
