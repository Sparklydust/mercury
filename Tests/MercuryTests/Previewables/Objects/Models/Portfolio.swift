//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises a stored property whose type is another owned, faked type.
@PreviewableFake
struct Portfolio {
  let account: Account
  let positions: [String]
  let updatedAt: Date
}
