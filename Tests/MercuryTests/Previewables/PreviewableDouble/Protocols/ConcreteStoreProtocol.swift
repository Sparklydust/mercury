//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Binds an associated response to a concrete scalar default.
@PreviewableDouble
protocol ConcreteStoreProtocol {
  associatedtype Element where Element == String
  func value() -> Element
}
