//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// The lexical position of an annotated declaration.
enum LexicalPosition {

  /// The declaration can be emitted, nested inside the supplied enclosing type names.
  case emittable(qualifier: [String])
  /// The declaration cannot be emitted, for the supplied human-readable reason.
  case unsupported(reason: String)
}
