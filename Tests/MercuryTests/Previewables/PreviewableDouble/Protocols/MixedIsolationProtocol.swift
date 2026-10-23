//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Exercises nonisolated requirements on an otherwise isolated double.
@MainActor
@PreviewableDouble
protocol MixedIsolationProtocol {
  nonisolated var count: Int { get set }
  nonisolated func load(id: Int) -> String
  func store(_ payload: RecordedPayload)
}
