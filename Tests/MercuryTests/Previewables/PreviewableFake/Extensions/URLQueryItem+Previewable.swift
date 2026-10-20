//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises an external parameter list carrying an optional, which the resolver still defaults.
@PreviewableFake(parameters: [("name", String.self), ("value", String?.self)])
extension URLQueryItem {
  // Intentionally empty: `URLQueryItem` is a Foundation type.
}
