//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Keeps a non-Sendable method response local across async observation.
@PreviewableDouble
protocol LegacyAsyncSpyProtocol {

  func load() async -> Session
}
