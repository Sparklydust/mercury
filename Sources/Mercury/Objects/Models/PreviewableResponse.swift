//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// Retains a configured response, including an explicitly typed optional nil.
struct PreviewableResponse<Value> {

  let value: Value
}

extension PreviewableResponse: Sendable where Value: Sendable {
  // Intentionally empty: Conformance to Sendable
}
