//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises recognition of a stored property with an observer.
@PreviewableFake
struct ObservedValue {
  var count: Int { didSet {} }
}
