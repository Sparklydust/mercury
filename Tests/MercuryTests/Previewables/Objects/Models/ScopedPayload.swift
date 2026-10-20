//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// A mutable actor-confined payload used to verify static recording isolation.
@MainActor
final class ScopedPayload {
  var value = 0
}
