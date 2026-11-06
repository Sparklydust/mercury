//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Exercises equivalent inherited signatures and independent overload responses.
@PreviewableDouble
protocol OverloadedServiceProtocol: CanonicalServiceProtocol, Sendable {
  func load(id: Swift.Int) -> String
  func load(id: String) -> String
  func load(name: String) -> String
}
