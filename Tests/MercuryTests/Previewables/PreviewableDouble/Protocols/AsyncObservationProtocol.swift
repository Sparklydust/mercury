//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Keeps intermediate UI state and non-Sendable responses on the main actor.
@MainActor
@PreviewableDouble
protocol AsyncObservationProtocol {

  func load() async throws -> String
  var payload: Session { get async }
}
