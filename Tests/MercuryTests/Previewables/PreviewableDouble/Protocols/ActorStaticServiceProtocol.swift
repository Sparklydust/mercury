//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Keeps static arguments and responses on the protocol actor.
@MainActor
@PreviewableDouble
protocol ActorStaticServiceProtocol {
  static func store(_ value: ScopedPayload) -> ScopedPayload?
}
