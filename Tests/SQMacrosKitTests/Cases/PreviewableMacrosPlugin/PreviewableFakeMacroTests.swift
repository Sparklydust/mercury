//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

#if canImport(PreviewableMacrosPlugin)
@testable import PreviewableMacrosPlugin
#endif
import SwiftSyntaxMacroExpansion
import Testing
@testable import SQMacrosKit

/// Verifies the expansion and diagnostics of `@PreviewableFake`.
@Suite
struct PreviewableFakeMacroTests {

#if canImport(PreviewableMacrosPlugin)
    // Macro implementations are compiler plugins built only for the host toolchain, so the
    // expansion tests below compile on macOS and are excluded on every other destination.
    private let macroSpecs: [String: MacroSpec] = [
        "PreviewableFake": .init(type: PreviewableFakeMacro.self)
    ]

    @Test
    func previewableFake_declarationIsEnum_diagnosticIsEmitted() {
        expectMacroExpansion(
            """
            @PreviewableFake
            enum Model {}
            """,
            expandedSource: """
            enum Model {}
            """,
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
        expectMacroExpansion(
            """
            @PreviewableFake
            struct Model {
              let value: Int
            }
            """,
            expandedSource: """
            struct Model {
              let value: Int
            }
            """,
            macroSpecs: macroSpecs
        )
    }

    @Test
    func previewableFake_extensionDeclaresMembers_expansionIsAccepted() {
        expectMacroExpansion(
            """
            @PreviewableFake(members: [("token", String.self)])
            extension Token {}
            """,
            expandedSource: """
            extension Token {}
            """,
            macroSpecs: macroSpecs
        )
    }

    @Test
    func previewableFake_extensionDeclaresNoMembers_diagnosticIsEmitted() {
        expectMacroExpansion(
            """
            @PreviewableFake
            extension Token {}
            """,
            expandedSource: """
            extension Token {}
            """,
            diagnostics: [
                .init(
                    message: """
                    @PreviewableFake cannot read a type declared outside this module \
                    — list its initializer parameters in 'members:'
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
        expectMacroExpansion(
            """
            @PreviewableFake(members: [("token", String.self)])
            extension Token where Element: Equatable {}
            """,
            expandedSource: """
            extension Token where Element: Equatable {}
            """,
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
    func previewableFake_ownedTypeDeclaresMembers_diagnosticIsEmitted() {
        expectMacroExpansion(
            """
            @PreviewableFake(members: [("value", Int.self)])
            struct Model {
              let value: Int
            }
            """,
            expandedSource: """
            struct Model {
              let value: Int
            }
            """,
            diagnostics: [
                .init(
                    message: """
                    @PreviewableFake reads the stored properties of a type declared in this module \
                    — remove 'members:'
                    """,
                    line: 1,
                    column: 1
                )
            ],
            macroSpecs: macroSpecs
        )
    }
#endif
}
