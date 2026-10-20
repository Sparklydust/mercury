//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// Exercises typed and explicitly labeled subscript overloads.
@PreviewableDouble
protocol IndexedServiceProtocol: Sendable {
  subscript(_ index: NonHashableIndex) -> String { get set }
  subscript(name name: String) -> Int { get }
}
