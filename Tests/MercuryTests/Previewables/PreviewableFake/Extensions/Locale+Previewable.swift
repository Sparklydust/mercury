//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises a type declared outside the module, whose initializer the generator cannot read.
@PreviewableFake(parameters: [("identifier", String.self)])
extension Locale {
  // Intentionally empty: `Locale` is a Foundation type.
}
