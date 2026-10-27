//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore
import Testing

struct PreviewableSourceGeneratorTests {

  @Test
  func generator_inputsAreUnchanged_outputIsIdentical() throws {
    let source = "@PreviewableFake struct Model { let name: String; let title: String }"
    let expected = try PreviewableSourceGenerator.generate(from: [source])

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(result == expected, "Unchanged inputs must generate identical defaults and declarations.")
  }

  @Test
  func generator_inputOrderChanges_outputIsIdentical() throws {
    let files = [
      PreviewableSourceFile(path: "A.swift", text: "@PreviewableFake struct First { let name: String }"),
      PreviewableSourceFile(path: "B.swift", text: "@PreviewableFake struct Second { let name: String }")
    ]
    let expected = try PreviewableSourceGenerator.generate(from: files)

    let result = try PreviewableSourceGenerator.generate(from: files.reversed())

    #expect(result == expected, "Build-system enumeration order must not change generated source.")
  }

  @Test
  func generator_declarationIsUnsupported_diagnosticIncludesSourceLocation() throws {
    let file = PreviewableSourceFile(
      path: "Service.swift",
      text: """
        import Foundation

        @PreviewableDouble
        protocol ServiceProtocol: Codable { var name: String { get } }
        """
    )
    let expected = ("Service.swift", 3, 1)

    let diagnostic = try #require(generatorDiagnostic(for: file))
    let result = (diagnostic.path, diagnostic.line, diagnostic.column)

    #expect(result == expected, "The diagnostic must identify the annotation's file, line, and column.")
  }

  @Test
  func generator_declarationIsUnsupported_diagnosticDescriptionUsesCompilerFormat() throws {
    let file = PreviewableSourceFile(
      path: "Service.swift",
      text: """
        import Foundation

        @PreviewableDouble
        protocol ServiceProtocol: Codable { var name: String { get } }
        """
    )
    let expected = "Service.swift:3:1: error: "

    let diagnostic = try #require(generatorDiagnostic(for: file))
    let result = diagnostic.description

    #expect(result.hasPrefix(expected), "The diagnostic description must use the compiler's source-location format.")
  }

  @Test(arguments: [
    """
    enum Namespace {
      @PreviewableDouble
      protocol ServiceProtocol { var name: String { get } }
    }
    """,
    """
    enum Namespace {
      @PreviewableFake
      struct Model { let value: String }
    }
    """
  ])
  func generator_declarationIsNested_outputIsGenerated(_ source: String) throws {
    let expected = "Namespace."

    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains(expected),
      "Nested declarations must generate qualified output rather than nothing."
    )
  }

  @Test
  func generator_declarationIsInsideConditionalCompilation_diagnosticIsEmitted() {
    let source = """
      #if DEBUG
      @PreviewableDouble
      protocol ServiceProtocol { var name: String { get } }
      #endif
      """

    let result = generatorDiagnosticMessage(for: source)

    #expect(
      result?.contains("declared inside a #if block") == true,
      "A declaration the generator never visits must name the reason rather than be silently skipped."
    )
  }

  @Test
  func generator_declarationIsGenerated_diagnosticsAreRemappedOntoTheAnnotation() throws {
    let sources = [
      PreviewableSourceFile(
        path: "Models.swift",
        text: """
          import Foundation

          @PreviewableFake
          struct Model { let value: String }
          """
      )
    ]
    let expected = "#sourceLocation(file: \"Models.swift\", line: 3)"

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      result.contains(expected),
      "A generated declaration must carry the location of the annotation that asked for it."
    )
  }

  @Test
  func generator_declarationIsGenerated_remappingIsClosedAfterEachDeclaration() throws {
    let sources = [
      "@PreviewableFake\nstruct Model { let value: String }"
    ]

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      result.components(separatedBy: "#sourceLocation()").count
        == result.components(separatedBy: "#sourceLocation(file:").count,
      "Every remapping must be closed, or it would swallow the declarations that follow it."
    )
  }

  @Test(
    arguments: ["private", "fileprivate"],
    ["@PreviewableFake struct Model { let value: Int }", "@PreviewableDouble protocol Service {}"]
  )
  func generator_annotationHasInaccessibleAncestor_diagnosticIsEmitted(_ access: String, _ declaration: String) {
    let source = "\(access) enum Scope { \(declaration) }"
    let expected = "inside a private or fileprivate type"

    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains(expected) == true, "Annotations inside inaccessible ancestors must fail before emission.")
  }

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
      "@PreviewableFake struct Model<T> { let value: T }",
      "generic parameter 'T'"
    ),
    (
      "@PreviewableDouble protocol ServiceProtocol { var kind: any ExternalKind { get } }",
      "existential type 'ExternalKind'"
    ),
    (
      "@PreviewableDouble protocol ServiceProtocol { var failure: any Error { get } }",
      "existential type 'Swift.Error'"
    ),
    (
      "@PreviewableDouble protocol ServiceProtocol { var failure: Error { get } }",
      "existential type 'Swift.Error'"
    ),
    (
      "@PreviewableFake struct Model { let payload: Codable }",
      "existential type 'Swift.Codable'"
    ),
    (
      "@PreviewableDouble protocol ServiceProtocol { var value: Any { get } }",
      "existential type 'Any'"
    ),
    (
      "@PreviewableDouble protocol ServiceProtocol { var owner: AnyObject { get } }",
      "existential type 'Swift.AnyObject'"
    ),
    (
      "@PreviewableDouble protocol ServiceProtocol { func stop() -> Never }",
      "uninhabited type 'Never'"
    ),
    (
      "struct Local { let value: Int }\n@PreviewableFake struct Model { let local: Local }",
      "must be annotated with @PreviewableFake"
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
    )
  ])
  func generator_defaultCannotBeConstructed_diagnosticExplainsFailure(_ source: String, _ expected: String) {
    let result = generatorDiagnosticMessage(for: source)

    #expect(result?.contains(expected) == true, "The diagnostic must contain `\(expected)`.")
  }
}
