//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore
import Testing

@Suite
struct PreviewableSourceGeneratorTests {

    @Test
    func generator_declarationIsUnsupported_diagnosticPointsAtTheSourceLine() throws {
        let file = PreviewableSourceFile(
            path: "Service.swift",
            text: """
            import Foundation

            @PreviewableDouble
            protocol ServiceProtocol: Codable { var name: String { get } }
            """
        )

        let diagnostic = try #require(generatorDiagnostic(for: file))

        #expect(diagnostic.path == "Service.swift")
        #expect(diagnostic.line == 3)
        #expect(diagnostic.description.hasPrefix("Service.swift:3:1: error: "))
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
        let result = try PreviewableSourceGenerator.generate(from: [source])

        #expect(
            result.contains("Namespace."),
            "Nested declarations must generate qualified output rather than nothing."
        )
    }

    @Test
    func generator_declarationIsInsideConditionalCompilation_diagnosticIsEmitted() {
        let message = generatorDiagnosticMessage(for: """
            #if DEBUG
            @PreviewableDouble
            protocol ServiceProtocol { var name: String { get } }
            #endif
            """)

        #expect(
            message?.contains("declared inside a #if block") == true,
            "A declaration the generator never visits must name the reason rather than be silently skipped."
        )
    }

    @Test
    func generator_declarationIsGenerated_diagnosticsAreRemappedOntoTheAnnotation() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            PreviewableSourceFile(
                path: "Models.swift",
                text: """
                import Foundation

                @PreviewableFake
                struct Model { let value: String }
                """
            )
        ])

        #expect(
            result.contains("#sourceLocation(file: \"Models.swift\", line: 3)"),
            "A generated declaration must carry the location of the annotation that asked for it."
        )
    }

    @Test
    func generator_declarationIsGenerated_remappingIsClosedAfterEachDeclaration() throws {
        let result = try PreviewableSourceGenerator.generate(from: [
            "@PreviewableFake\nstruct Model { let value: String }"
        ])

        #expect(
            result.components(separatedBy: "#sourceLocation()").count
            == result.components(separatedBy: "#sourceLocation(file:").count,
            "Every remapping must be closed, or it would swallow the declarations that follow it."
        )
    }
}
