//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// A base protocol whose requirements must be flattened into every derived double.
@PreviewableDouble
protocol IdentifiableServiceProtocol: Sendable {
  var identifier: UUID { get }
  func reset()
}
