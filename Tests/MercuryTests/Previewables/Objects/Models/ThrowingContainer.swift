//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises propagation of a nested factory throwing effect.
@PreviewableFake
struct ThrowingContainer {
  let value: CheckedValue
}
