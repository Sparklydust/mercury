//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// A validation failure paired with the declaration the developer has to change.
struct GenerationFailure {

  /// The annotation responsible for the validation failure.
  let annotation: AnnotatedDeclaration
  /// The source diagnostic explaining the validation failure.
  let message: String
}
