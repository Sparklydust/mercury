//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
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
