//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// An index that supports recording without supporting hash-based lookup.
struct NonHashableIndex: Sendable {
  let value: Int
}
