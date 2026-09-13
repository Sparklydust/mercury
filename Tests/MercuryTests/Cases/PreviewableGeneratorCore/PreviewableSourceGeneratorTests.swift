//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

@Suite
struct PreviewableSourceGeneratorTests {

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
    """,
  ])
  func generator_declarationIsNested_outputIsGenerated(_ source: String) throws {
    let result = try PreviewableSourceGenerator.generate(from: [source])

    #expect(
      result.contains("Namespace."),
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

    let result = try PreviewableSourceGenerator.generate(from: sources)

    #expect(
      result.contains("#sourceLocation(file: \"Models.swift\", line: 3)"),
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
}
