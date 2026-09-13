//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// A declaration carrying a Previewable macro.
struct AnnotatedDeclaration {

    let annotation: PreviewableAnnotation
    /// The attribute as written, kept so the generator can read arguments the collector does not interpret.
    let attribute: AttributeSyntax
    let declaration: DeclSyntax
    let name: String
    let position: LexicalPosition
    let fileIndex: Int
    let absolutePosition: AbsolutePosition

    /// The declaration name qualified by its enclosing types.
    var qualifiedName: String {
        guard case .emittable(let qualifier) = position else { return name }
        return (qualifier + [name]).joined(separator: ".")
    }
}
