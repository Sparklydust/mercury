//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
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
