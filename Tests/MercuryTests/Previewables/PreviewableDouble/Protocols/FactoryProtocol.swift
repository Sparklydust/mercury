//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises an initializer requirement, which a double must witness to conform at all.
@PreviewableDouble
protocol FactoryProtocol {
  init(name: String)
  func reload()
}
