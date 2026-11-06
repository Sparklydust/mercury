//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// An index that supports recording without supporting hash-based lookup.
struct NonHashableIndex: Sendable {
  let value: Int
}
