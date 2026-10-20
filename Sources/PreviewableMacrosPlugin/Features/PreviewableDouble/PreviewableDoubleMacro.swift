//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax
import SwiftSyntaxMacros

/// Validates protocol declarations annotated with `PreviewableDouble`.
struct PreviewableDoubleMacro: PeerMacro {

  /// Validates that the attached declaration supports Previewable double generation.
  /// - Parameters:
  ///   - node: The attached macro attribute.
  ///   - declaration: The declaration to validate.
  ///   - context: The compiler expansion context; validation emits no peers.
  /// - Returns: An empty peer list; the build tool generates the declarations.
  /// - Throws: When the declaration is not a supported protocol.
  static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard declaration.is(ProtocolDeclSyntax.self)
    else { throw PreviewableMacroError.message("@PreviewableDouble can only be applied to a protocol") }
    _ = node
    return []
  }
}
