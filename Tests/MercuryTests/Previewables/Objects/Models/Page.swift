//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises a generic type, whose optional generic value defaults to nil.
@PreviewableFake
struct Page<Element> {
  let element: Element?
  let index: Int
}
