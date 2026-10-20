//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Provides one lexical scope for same-named nested fake types.
enum FirstNamespace {
  enum Kind { case first }

  @PreviewableFake
  struct Model { let kind: Kind }
}
