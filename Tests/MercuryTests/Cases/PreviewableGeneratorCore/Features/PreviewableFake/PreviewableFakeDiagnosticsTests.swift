//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

@Suite
struct PreviewableFakeDiagnosticsTests {

  @Test(arguments: [
    (
      """
      @PreviewableFake
      struct Model { private let secret: String; let value: String }
      """,
      "private property 'secret' appears in the memberwise initializer"
    ),
    (
      """
      @PreviewableFake
      struct Model { private var secret: String = "x"; let value: String }
      """,
      "private property 'secret' appears in the memberwise initializer"
    ),
    (
      """
      @PreviewableFake
      final class Model { let value: String }
      """,
      "classes require mutable fake properties and an accessible init()"
    ),
    (
      """
      @PreviewableFake
      final class Model { var value: String; init(value: String) { self.value = value } }
      """,
      "the generated initializer calls 'init()'"
    ),
    (
      """
      @PreviewableFake
      final class Model { var value: String }
      """,
      "'value' has no initial value, so the class has no 'init()' to call"
    ),
    (
      """
      @PreviewableFake
      struct Model { let value: String; init(from other: Model) { self = other } }
      """,
      "declaring an initializer suppresses the memberwise one"
    ),
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
