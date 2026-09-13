//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// Validates protocol declarations annotated with `PreviewableDouble`.
struct PreviewableDoubleMacro: PeerMacro {

    /// Validates that the attached declaration supports Previewable double generation.
    /// - Throws: When the declaration is not a supported protocol.
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDeclaration = declaration.as(ProtocolDeclSyntax.self)
        else { throw PreviewableMacroError.message("@PreviewableDouble can only be applied to a protocol") }

        guard protocolDeclaration.primaryAssociatedTypeClause == .none,
              protocolDeclaration.genericWhereClause == .none
        else {
            throw PreviewableMacroError
                .message("@PreviewableDouble does not support protocols with associated types or generic constraints")
        }

        _ = node
        return []
    }
}
