//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Provides one lexical scope for same-named nested fake types.
enum FirstNamespace {
  enum Kind { case first }

  @PreviewableFake
  struct Model { let kind: Kind }
}
