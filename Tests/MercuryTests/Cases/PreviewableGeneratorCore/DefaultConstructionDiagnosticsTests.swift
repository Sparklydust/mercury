//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

struct DefaultConstructionDiagnosticsTests {

  @Test(arguments: [
    (
      "struct ServiceDouble {}\n@PreviewableDouble protocol ServiceProtocol {}",
      "conflicts with an existing declaration"
    ),
    (
      "@PreviewableDouble protocol ServiceProtocol { var calledMethods: [String] { get } }",
      "conflicts with a generated member"
    ),
    (
      "@PreviewableDouble protocol RecursiveProtocol { var next: any RecursiveProtocol { get } }",
      "recursive default construction"
    ),
    (
      "@PreviewableFake final class Model { var next: Swift.Result<Model, any Error> = .failure(Failure()) }",
      "recursive default construction"
    ),
    (
      "@PreviewableFake struct Model { let value: ExternalValue }",
      "Model.value"
    ),
    (
      "@PreviewableFake struct Model<T> { let value: T }",
      "generic parameter 'T'"
    ),
    (
      "@PreviewableFake private struct Model { let value: Int }",
      "private or fileprivate type"
    ),
    (
      "@PreviewableFake struct Model { let value: Int; init(value: String) { self.value = 0 } }",
      "add an accessible 'init(value:)'"
    ),
    (
      """
      @PreviewableFake struct Model { let value: Int; init(value: Int) throws { self.value = value } }
      @PreviewableDouble protocol ServiceProtocol { var value: Model { get } }
      """,
      "nonthrowing double"
    ),
  ])
  func generator_defaultCannotBeConstructed_diagnosticExplainsFailure(_ source: String, _ expected: String) {
    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains(expected) == true, "The diagnostic must contain `\(expected)`.")
  }
}
