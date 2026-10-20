//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises recognition of a stored property with an observer.
@PreviewableFake
struct ObservedValue {
  var count: Int { didSet {} }
}
