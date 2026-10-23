//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises a class, which receives a convenience initializer alongside its factory.
@PreviewableFake
final class Session {
  var token: String = ""
  var expiresAt: Date = .now

  init() {}
}
