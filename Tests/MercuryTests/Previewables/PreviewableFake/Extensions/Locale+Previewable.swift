//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises a type declared outside the module, whose initializer the generator cannot read.
@PreviewableFake(parameters: [("identifier", String.self)])
extension Locale {
  // Intentionally empty: `Locale` is a Foundation type.
}
