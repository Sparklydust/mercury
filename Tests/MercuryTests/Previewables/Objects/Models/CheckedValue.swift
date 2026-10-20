//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises a throwing initializer that accepts only positive counts.
@PreviewableFake
struct CheckedValue {
  let count: Int

  init(count: Int) throws {
    guard count > 0 else { throw ConstructionError.invalid }
    self.count = count
  }
}
