//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// Validates declarations annotated with `PreviewableFake` for fake-factory generation.
///
/// The macro is a peer macro that expands to nothing: the build tool plugin writes the factory. A peer role is what
/// lets the attribute sit on an extension, which an extension role forbids and which the `parameters:` form requires.
struct PreviewableFakeMacro: PeerMacro {

    /// Validates that the attached declaration supports fake-factory generation.
    /// - Throws: When the declaration is neither a structure, a class nor an extension, or when it disagrees with
    ///   the presence of the `parameters:` argument.
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let declaresParameters = node.arguments != nil

        if let extensionDeclaration = declaration.as(ExtensionDeclSyntax.self) {
            try validate(extensionDeclaration, declaresParameters: declaresParameters)
        } else if declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self) {
            guard !declaresParameters else {
                throw PreviewableMacroError.message(
                    """
                    @PreviewableFake reads the stored properties of a type declared in this module \
                    — remove 'parameters:'
                    """
                )
            }
        } else {
            throw PreviewableMacroError.message(
                """
                @PreviewableFake can only be applied to a structure, a class, or an extension of a type declared \
                outside this module
                """
            )
        }

        _ = context
        return []
    }
}

private extension PreviewableFakeMacro {

    /// Validates an extension the generator has to take on trust, having never read the extended type.
    static func validate(
        _ declaration: ExtensionDeclSyntax,
        declaresParameters: Bool
    ) throws {
        guard declaresParameters else {
            throw PreviewableMacroError.message(
                """
                @PreviewableFake cannot read a type declared outside this module \
                — declare its initializer parameters in 'parameters:'
                """
            )
        }
        guard declaration.genericWhereClause == nil else {
            throw PreviewableMacroError.message(
                "@PreviewableFake does not support constrained extensions — remove the 'where' clause"
            )
        }
    }
}
