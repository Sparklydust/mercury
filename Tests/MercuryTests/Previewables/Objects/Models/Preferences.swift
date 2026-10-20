//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises a private property that stays private because it carries its own value.
@PreviewableFake
struct Preferences {
  private let storageKey: String = "preferences"
  let locale: String
  let isCompact: Bool
}
