//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// Owns the custom-actor argument records used by concurrency tests.
@globalActor
actor RecordingActor {
  static let shared = RecordingActor()
}
