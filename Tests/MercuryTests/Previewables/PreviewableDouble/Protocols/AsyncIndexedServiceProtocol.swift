//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// Provides an asynchronous throwing getter for subscript validation.
@PreviewableDouble
protocol AsyncIndexedServiceProtocol: Sendable {
  subscript(_ index: Int) -> String { get async throws }
}
