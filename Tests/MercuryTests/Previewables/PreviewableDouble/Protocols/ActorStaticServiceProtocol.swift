//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// Keeps static arguments and responses on the protocol actor.
@MainActor
@PreviewableDouble
protocol ActorStaticServiceProtocol {
  static func store(_ value: ScopedPayload) -> ScopedPayload?
}
