//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// Validates declarations annotated with `PreviewableFake` for fake-factory generation.
///
/// The macro is a peer macro that expands to nothing: the build tool plugin writes the factory. A peer role is what
/// lets the attribute sit on an extension, which an extension role forbids and which the `members:` form requires.
struct PreviewableFakeMacro: PeerMacro {

    /// Validates that the attached declaration supports fake-factory generation.
    /// - Throws: When the declaration is neither a structure, a class nor an extension, or when it disagrees with
    ///   the presence of the `members:` argument.
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let declaresMembers = node.arguments != nil

        if let extensionDeclaration = declaration.as(ExtensionDeclSyntax.self) {
            try validate(extensionDeclaration, declaresMembers: declaresMembers)
        } else if declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self) {
            guard !declaresMembers else {
                throw PreviewableMacroError.message(
                    """
                    @PreviewableFake reads the stored properties of a type declared in this module \
                    — remove 'members:'
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
        declaresMembers: Bool
    ) throws {
        guard declaresMembers else {
            throw PreviewableMacroError.message(
                """
                @PreviewableFake cannot read a type declared outside this module \
                — list its initializer parameters in 'members:'
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
