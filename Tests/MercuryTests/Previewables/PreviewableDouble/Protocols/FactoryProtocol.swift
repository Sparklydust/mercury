//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises an initializer requirement, which a double must witness to conform at all.
@PreviewableDouble
protocol FactoryProtocol {
  init(name: String)
  func reload()
}
