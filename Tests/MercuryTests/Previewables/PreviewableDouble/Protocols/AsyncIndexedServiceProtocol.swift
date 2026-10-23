//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Provides an asynchronous throwing getter for subscript validation.
@PreviewableDouble
protocol AsyncIndexedServiceProtocol: Sendable {
  subscript(_ index: Int) -> String { get async throws }
}
