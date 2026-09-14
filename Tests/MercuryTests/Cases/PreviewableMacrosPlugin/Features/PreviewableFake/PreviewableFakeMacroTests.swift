//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntaxMacroExpansion
import Testing
#if canImport(PreviewableMacrosPlugin)
@testable import PreviewableMacrosPlugin
#endif

struct PreviewableFakeMacroTests {

  #if canImport(PreviewableMacrosPlugin)
    // Macro implementations are compiler plugins built only for the host toolchain, so the
    // expansion tests below compile on macOS and are excluded on every other destination.
    private let macroSpecs: [String: MacroSpec] = [
      "PreviewableFake": .init(type: PreviewableFakeMacro.self)
    ]

    @Test
    func previewableFake_declarationIsEnum_diagnosticIsEmitted() {
      let source = """
        @PreviewableFake
        enum Model {}
        """
      let expected = """
        enum Model {}
        """

      expectMacroExpansion(
        source,
        expandedSource: expected,
        diagnostics: [
          .init(
            message: """
              @PreviewableFake can only be applied to a structure, a class, or an extension of a type \
              declared outside this module
              """,
            line: 1,
            column: 1
          )
        ],
        macroSpecs: macroSpecs
      )
    }

    @Test
    func previewableFake_declarationHasStoredProperties_expansionIsAccepted() {
      let source = """
        @PreviewableFake
        struct Model {
          let value: Int
        }
        """
      let expected = """
        struct Model {
          let value: Int
        }
        """

      expectMacroExpansion(
        source,
        expandedSource: expected,
        macroSpecs: macroSpecs
      )
    }

    @Test
    func previewableFake_extensionDeclaresParameters_expansionIsAccepted() {
      let source = """
        @PreviewableFake(parameters: [("token", String.self)])
        extension Token {}
        """
      let expected = """
        extension Token {}
        """

      expectMacroExpansion(
        source,
        expandedSource: expected,
        macroSpecs: macroSpecs
      )
    }

    @Test
    func previewableFake_extensionDeclaresNoParameters_diagnosticIsEmitted() {
      let source = """
        @PreviewableFake
        extension Token {}
        """
      let expected = """
        extension Token {}
        """

      expectMacroExpansion(
        source,
        expandedSource: expected,
        diagnostics: [
          .init(
            message: """
              @PreviewableFake cannot read a type declared outside this module \
              — declare its initializer parameters in 'parameters:'
              """,
            line: 1,
            column: 1
          )
        ],
        macroSpecs: macroSpecs
      )
    }

    @Test
    func previewableFake_extensionIsConstrained_diagnosticIsEmitted() {
      let source = """
        @PreviewableFake(parameters: [("token", String.self)])
        extension Token where Element: Equatable {}
        """
      let expected = """
        extension Token where Element: Equatable {}
        """

      expectMacroExpansion(
        source,
        expandedSource: expected,
        diagnostics: [
          .init(
            message: "@PreviewableFake does not support constrained extensions — remove the 'where' clause",
            line: 1,
            column: 1
          )
        ],
        macroSpecs: macroSpecs
      )
    }

    @Test
    func previewableFake_ownedTypeDeclaresParameters_diagnosticIsEmitted() {
      let source = """
        @PreviewableFake(parameters: [("value", Int.self)])
        struct Model {
          let value: Int
        }
        """
      let expected = """
        struct Model {
          let value: Int
        }
        """

      expectMacroExpansion(
        source,
        expandedSource: expected,
        diagnostics: [
          .init(
            message: """
              @PreviewableFake reads the stored properties of a type declared in this module \
              — remove 'parameters:'
              """,
            line: 1,
            column: 1
          )
        ],
        macroSpecs: macroSpecs
      )
    }

    @Test(arguments: ["struct", "final class"])
    func previewableFake_emptyParenthesesAreUsed_expansionIsAccepted(_ kind: String) {
      let source = """
        @PreviewableFake()
        \(kind) Model {
          var value = 0
        }
        """
      let expected = """
        \(kind) Model {
          var value = 0
        }
        """

      expectMacroExpansion(source, expandedSource: expected, macroSpecs: macroSpecs)
    }

  #endif
}
