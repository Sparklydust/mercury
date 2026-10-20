//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

struct GenericResponseValidatorTests {

  @Test(arguments: [
    "<Value: Sendable>() -> @Sendable () -> Value",
    "<Value>() -> @MainActor () -> Value",
    "<Value: Sendable>() -> [String: Value]",
    "<Value: Sendable>() -> (Value, Value)",
    "<Values: Collection & Sendable>(_ values: Values) -> Values.Element where Values.Element: Sendable"
  ])
  func response_componentsAreSendable_responseStoreIsGenerated(_ signature: String) throws {
    let source = "@PreviewableDouble protocol Service: Sendable { func make\(signature) }"
    let expected = "let makeStub: PreviewableResponses"

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result.contains(expected), "Sendable compound responses must use synchronized storage.")
  }

  @Test(arguments: [
    ("<Value: Sendable>() -> () -> Value", "requires @Sendable"),
    ("<Values: Collection & Sendable>(_ values: Values) -> Values.Element", "Values.Element: Sendable")
  ])
  func response_componentLacksSendability_diagnosticNamesConstraint(
    _ signature: String,
    _ expected: String
  ) {
    let source = "@PreviewableDouble protocol Service: Sendable { func make\(signature) }"

    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains(expected) == true, "The diagnostic must identify the missing response constraint.")
  }
}
