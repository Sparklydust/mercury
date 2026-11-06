//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Owns the custom-actor argument records used by concurrency tests.
@globalActor
actor RecordingActor {
  static let shared = RecordingActor()
}
