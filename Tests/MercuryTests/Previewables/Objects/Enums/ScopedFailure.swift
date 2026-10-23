//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Identifies queue entries independently of concurrent caller scheduling.
enum ScopedFailure: Error, Equatable {
  case numbered(Int)
}
