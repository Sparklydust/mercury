//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises propagation of a nested factory throwing effect.
@PreviewableFake
struct ThrowingContainer {
  let value: CheckedValue
}
