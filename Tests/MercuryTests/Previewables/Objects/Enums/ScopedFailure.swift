//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// Identifies queue entries independently of concurrent caller scheduling.
enum ScopedFailure: Error, Equatable {
  case numbered(Int)
}
