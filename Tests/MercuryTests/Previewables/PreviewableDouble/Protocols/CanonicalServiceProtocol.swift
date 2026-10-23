//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Supplies an inherited signature spelled through a local alias.
protocol CanonicalServiceProtocol {
  func load(id: CanonicalIdentifier) -> String
}
