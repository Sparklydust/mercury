//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// A mutable actor-confined payload used to verify static recording isolation.
@MainActor
final class ScopedPayload {
  var value = 0
}
