//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises a globally isolated type, whose initializer the factory can only reach on its actor.
@PreviewableFake
@MainActor
final class ViewState {
  var title: String = ""
  var isLoading: Bool = false

  init() {}
}
