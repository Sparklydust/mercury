//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises a global-actor isolated protocol.
@MainActor
@PreviewableDouble
protocol PresentationServiceProtocol {
  var headline: String { get }
  func present()
}
