//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// Binds an associated response to a concrete scalar default.
@PreviewableDouble
protocol ConcreteStoreProtocol {
  associatedtype Element where Element == String
  func value() -> Element
}
