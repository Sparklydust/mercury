//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

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

  @Test(arguments: ["MainActor", "UIContext", "External.UIContext"])
  func generator_initializerHasActorAttribute_diagnosticIsEmitted(_ actorName: String) {
    let source = """
      @PreviewableFake
      struct Model {
        let value: Int
        @\(actorName) init(value: Int) { self.value = value }
      }
      """
    let expected = "does not support initializer attribute '@\(actorName)'"

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result?.contains(expected) == true, "Initializer-specific actor isolation must produce a source diagnostic.")
  }

  @Test(arguments: ["String", "Wrong", "Swift.Int"])
  func generator_initializerTypeIsNotEquivalent_diagnosticIsEmitted(_ parameterType: String) {
    let source = """
      struct Int {}
      typealias Wrong = String
      @PreviewableFake
      struct Model {
        let value: Int
        init(value: \(parameterType)) { fatalError() }
      }
      """
    let expected = "add an accessible 'init(value:)'"

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result?.contains(expected) == true, "Initializer matching must preserve local types that shadow Swift names.")
  }

  @Test(arguments: ["Namespace.Helper", "[Namespace.Helper]", "(Namespace.Helper, Int)"])
  func generator_publicFactoryUsesInternalQualifiedType_diagnosticIsEmitted(_ propertyType: String) {
    let source = """
      public enum Namespace {
        @PreviewableFake
        struct Helper { let value: Int }
      }
      @PreviewableFake
      public struct Model { let helper: \(propertyType) }
      """
    let expected = "uses the internal type 'Namespace.Helper'"

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result?.contains(expected) == true, "Access validation must inspect qualified types inside composite types.")
  }
}
