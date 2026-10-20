//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Provides mutable nested state for double independence checks.
@PreviewableDouble
protocol ChildServiceProtocol: Sendable {
  var count: Int { get set }
}
