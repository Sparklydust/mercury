//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

#if canImport(PreviewableMacrosPlugin)
@testable import PreviewableMacrosPlugin
#endif
import SwiftSyntaxMacroExpansion
import Testing
@testable import Mercury

@Suite
struct PreviewableDoubleMacroTests {

#if canImport(PreviewableMacrosPlugin)
  // Macro implementations are compiler plugins built only for the host toolchain, so the
  // expansion tests below compile on macOS and are excluded on every other destination.
  private let macroSpecs: [String: MacroSpec] = [
    "PreviewableDouble": .init(type: PreviewableDoubleMacro.self)
  ]

  @Test
  func previewableDouble_declarationIsNotProtocol_diagnosticIsEmitted() {
    expectMacroExpansion(
            """
            @PreviewableDouble
            struct Service {}
            """,
            expandedSource: """
            struct Service {}
            """,
            diagnostics: [
              .init(
                message: "@PreviewableDouble can only be applied to a protocol",
                line: 1,
                column: 1
              )
            ],
            macroSpecs: macroSpecs
    )
  }
#endif
}
