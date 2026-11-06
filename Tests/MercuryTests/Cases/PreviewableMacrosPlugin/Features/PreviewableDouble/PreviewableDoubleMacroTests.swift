//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntaxMacroExpansion
import Testing
#if MERCURY_BUILD_GENERATOR_FROM_SOURCE && canImport(PreviewableMacrosPlugin)
@testable import PreviewableMacrosPlugin
#elseif canImport(PreviewableMacrosTestsSupport)
@testable import PreviewableMacrosTestsSupport
#endif

struct PreviewableDoubleMacroTests {

  #if canImport(PreviewableMacrosTestsSupport) || canImport(PreviewableMacrosPlugin)
    // Macro expansion tests require the host compiler plugin and are excluded from device destinations.
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
