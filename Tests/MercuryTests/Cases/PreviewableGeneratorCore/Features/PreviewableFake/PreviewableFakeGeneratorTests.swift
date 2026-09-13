//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

@Suite
struct PreviewableFakeGeneratorTests {

  private let source = """
    import Foundation

    @PreviewableFake
    struct Model {
      let value: String
    }

    @PreviewableFake
    final class ReferenceModel {
      var value = String()

      init() {}
    }
    """

  @Test(arguments: [
    ") -> Model {\n    .init(",
    "convenience init(\n    value: String",
    ") -> ReferenceModel {\n    .init(",
  ])
  func generator_fakeIsAnnotated_expectedFactoryMemberIsGenerated(
    _ expected: String
  ) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "Generated source must contain `\(expected)`."
    )
  }

  @Test(arguments: [
    ("extension Model", true),
    ("value: String = { () -> String in preconditionFailure(", true),
    ("preconditionFailure(\"Model.fake(...) is unavailable", true),
    (".init(", false),
  ])
  func generator_fakeIsBuiltOutsideDebug_factoryContainsOnlyUnavailableConstruction(
    _ fragment: String,
    _ expected: Bool
  ) throws {
    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let releaseSource = try #require(
      generated.components(separatedBy: "#else\n").dropFirst().first?
        .components(separatedBy: "#endif").first
    )
    let result = releaseSource.contains(fragment)

    #expect(result == expected, "Release factory source must match the expected presence of `\(fragment)`.")
  }

  @Test
  func generator_genericFieldHasNoDefault_diagnosticIsEmitted() {
    let source = "@PreviewableFake\nstruct Page<Element> { let element: Element; let index: Int }"
    let expected = "cannot synthesise a default for generic parameter 'Element'"

    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains(expected) == true, "The diagnostic must identify the unsupported generic default.")
  }

  @Test
  func generator_propertyIsPrivateWithValue_itStaysPrivate() throws {
    let sources = [
      """
      @PreviewableFake
      struct Preferences {
        private let storageKey: String = "preferences"
        let locale: String
      }
      """
    ]

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      !result.contains("storageKey"),
      "A private property must never appear in the generated fake factory."
    )
  }

  @Test(arguments: [
    ("open ", false),
    ("public static func fake(", true),
  ])
  func generator_typeIsOpen_generatedMembersUseSupportedAccess(_ fragment: String, _ expected: Bool) throws {
    let source = """
      @PreviewableFake
      open class Portfolio {
        open var title: String = ""

        public init() {}
      }
      """

    let generated = try PreviewableSourceGenerator.generate(from: [source])
    let result = generated.contains(fragment)

    #expect(result == expected, "Generated members must replace open access with public access.")
  }

  @Test
  func generator_publicTypeHoldsLessVisibleType_diagnosticNamesBoth() {
    let expected = """
      @PreviewableFake cannot generate a public factory for 'Wrapper': its 'helper' parameter \
      uses the internal type 'Helper' — raise 'Helper' to public
      """

    let result = generatorDiagnosticMessage(
      for: """
        @PreviewableFake
        struct Helper { let identifier: Int }

        @PreviewableFake
        public struct Wrapper { let helper: Helper }
        """)

    #expect(
      result == expected,
      "A public factory cannot take an internal parameter, so the mismatch must be reported here."
    )
  }

  @Test
  func generator_publicTypeHoldsPublicType_factoryIsGenerated() throws {
    let sources = [
      """
      @PreviewableFake
      public struct Helper { public let identifier: Int }

      @PreviewableFake
      public struct Wrapper { public let helper: Helper }
      """
    ]

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      result.contains("public static func fake(\n    helper: Helper = Helper.fake()"),
      "Matching visibility must stay allowed, or the check would forbid the normal case."
    )
  }

  @Test(arguments: [
    "onDone: @escaping () -> Void",
    "convenience init(\n    onDone: @escaping () -> Void",
  ])
  func generator_propertyIsAClosure_factoryParameterEscapes(_ expected: String) throws {
    let sources = [
      """
      @PreviewableFake
      final class HandlerModel {
        var onDone: () -> Void = {}
        var onFail: ((Error) -> Void)?

        init() {}
      }
      """
    ]

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      result.contains(expected),
      "A non-escaping parameter cannot be stored by the initializer the factory calls."
    )
  }

  @Test
  func generator_propertyIsAnOptionalClosure_factoryParameterDoesNotEscape() throws {
    let sources = [
      """
      @PreviewableFake
      struct MaybeModel {
        let onDone: (() -> Void)?
      }
      """
    ]

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      !result.contains("@escaping"),
      "`@escaping` applies to function types only, so an optional closure must be left bare."
    )
  }
}
