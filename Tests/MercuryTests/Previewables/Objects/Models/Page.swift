//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises a generic type, whose optional generic value defaults to nil.
@PreviewableFake
struct Page<Element> {
  let element: Element?
  let index: Int
}
