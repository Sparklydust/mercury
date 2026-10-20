//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Provides a second lexical scope with a distinct enumeration default.
enum SecondNamespace {
  enum Kind { case second }

  @PreviewableFake
  struct Model { let kind: Kind }
}
