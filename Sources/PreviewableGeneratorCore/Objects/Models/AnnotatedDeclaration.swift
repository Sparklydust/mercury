//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// A declaration carrying a Previewable macro.
struct AnnotatedDeclaration {

  /// The feature selected by the attribute.
  let annotation: PreviewableAnnotation
  /// The attribute as written, kept so the generator can read arguments the collector does not interpret.
  let attribute: AttributeSyntax
  /// The syntax node carrying the attribute.
  let declaration: DeclSyntax
  /// The unqualified declaration name, or the written extended type name.
  let name: String
  /// The enclosing type path or the reason the location is unsupported.
  let position: LexicalPosition
  /// The zero-based index of the input file.
  let fileIndex: Int
  /// The declaration offset used to locate diagnostics.
  let absolutePosition: AbsolutePosition

  /// The declaration name qualified by its enclosing types.
  var qualifiedName: String {
    guard case .emittable(let qualifier) = position else { return name }
    return (qualifier + [name]).joined(separator: ".")
  }
}
