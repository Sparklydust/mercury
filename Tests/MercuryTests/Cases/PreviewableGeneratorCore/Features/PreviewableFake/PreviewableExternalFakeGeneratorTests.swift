//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

@Suite
struct PreviewableExternalFakeGeneratorTests {

  private static let externalSource = """
    import Foundation

    @PreviewableFake(parameters: [("token", String.self), ("expirationDate", Date.self)])
    extension AppCheckToken {}
    """

  @Test(arguments: [
    "extension AppCheckToken {",
    "static func fake(",
    "token: String = ",
    "expirationDate: Date = Date(timeIntervalSince1970: 1704067200)",
    ") -> AppCheckToken {",
    "token: token,",
    "expirationDate: expirationDate",
  ])
  func generator_extensionDeclaresParameters_factoryMatchesTheDeclaredParameters(_ expected: String) throws {
    let result = try PreviewableSourceGenerator.generate(from: [Self.externalSource])

    #expect(
      result.contains(expected),
      "A type the generator cannot read must produce the factory its declared parameters describe."
    )
  }

  @Test
  func generator_extensionDeclaresParameters_noConvenienceInitializerIsGenerated() throws {
    let result = try PreviewableSourceGenerator.generate(from: [Self.externalSource])

    #expect(
      !result.contains("convenience init("),
      "An initializer added from another module could not reach the extended type's stored properties."
    )
  }

  @Test
  func generator_externalTypeIsFaked_ownedPropertyDefaultsToIt() throws {
    let sources = [
      """
      \(Self.externalSource)

      @PreviewableFake
      struct Credentials {
        let appCheck: AppCheckToken
      }
      """
    ]

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      result.contains("appCheck: AppCheckToken = AppCheckToken.fake()"),
      "An annotated external type must be usable as a property type, exactly like an owned one."
    )
  }

  @Test
  func generator_extensionDeclaresNoParameters_diagnosticNamesTheMissingArgument() {
    let source = """
      @PreviewableFake
      extension AppCheckToken {}
      """
    let expected = """
      @PreviewableFake cannot read 'AppCheckToken', declared outside this module \
      — declare its initializer parameters in 'parameters:'
      """

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result == expected,
      "Without parameters the generator has nothing to describe the type, and must say so."
    )
  }

  @Test
  func generator_parameterIsNotANameTypePair_diagnosticIsEmitted() {
    let source = """
      @PreviewableFake(parameters: [("token", "String")])
      extension AppCheckToken {}
      """
    let expected = """
      @PreviewableFake expects every parameter of 'AppCheckToken' to read as \
      ('name', Type.self)
      """

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result == expected,
      "A member spelled as anything but a name and a metatype cannot be turned into a parameter."
    )
  }

  @Test
  func generator_parameterListIsEmpty_diagnosticIsEmitted() {
    let source = """
      @PreviewableFake(parameters: [])
      extension AppCheckToken {}
      """
    let expected = """
      @PreviewableFake requires at least one parameter for 'AppCheckToken' \
      — list the values its initializer takes
      """

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result == expected,
      "A factory taking no values would construct nothing the caller could vary."
    )
  }

  @Test
  func generator_parameterNameIsRepeated_diagnosticIsEmitted() {
    let source = """
      @PreviewableFake(parameters: [("token", String.self), ("token", Int.self)])
      extension AppCheckToken {}
      """
    let expected = "@PreviewableFake requires distinct parameter names for 'AppCheckToken'"

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result == expected,
      "Repeating a name would generate a factory with two identical parameter labels."
    )
  }

  @Test
  func generator_ownedTypeDeclaresParameters_diagnosticIsEmitted() {
    let source = """
      @PreviewableFake(parameters: [("value", Int.self)])
      struct Model { let value: Int }
      """
    let expected = """
      @PreviewableFake reads the stored properties of a type declared in this module \
      — remove 'parameters:'
      """

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result == expected,
      "Declared parameters and read stored properties could disagree, so only one of them may be given."
    )
  }

  @Test
  func generator_typeIsFakedTwice_diagnosticIsEmitted() {
    let source = """
      @PreviewableFake(parameters: [("token", String.self)])
      extension AppCheckToken {}

      @PreviewableFake(parameters: [("token", String.self)])
      extension AppCheckToken {}
      """
    let expected = """
      'AppCheckToken' is annotated with @PreviewableFake more than once \
      — keep a single annotation
      """

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result == expected,
      "Two annotations on the same type would generate the same factory twice."
    )
  }
}
