//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Retains a configured response, including an explicitly typed optional nil.
struct PreviewableResponse<Value> {

  let value: Value
}

extension PreviewableResponse: Sendable where Value: Sendable {
  // Intentionally empty: Conformance to Sendable
}
