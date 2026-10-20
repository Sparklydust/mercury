//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// Supplies an inherited signature spelled through a local alias.
protocol CanonicalServiceProtocol {
  func load(id: CanonicalIdentifier) -> String
}
