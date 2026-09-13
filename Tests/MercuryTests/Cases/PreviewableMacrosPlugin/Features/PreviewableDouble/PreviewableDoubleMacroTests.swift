//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntaxMacroExpansion
import Testing
#if canImport(PreviewableMacrosPlugin)
@testable import PreviewableMacrosPlugin
#endif

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
      let source = """
        @PreviewableDouble
        struct Service {}
        """
      let expected = """
        struct Service {}
        """

      expectMacroExpansion(
        source,
        expandedSource: expected,
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
