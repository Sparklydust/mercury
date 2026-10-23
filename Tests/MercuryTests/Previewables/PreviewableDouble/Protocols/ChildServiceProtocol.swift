//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Provides mutable nested state for double independence checks.
@PreviewableDouble
protocol ChildServiceProtocol: Sendable {
  var count: Int { get set }
}
