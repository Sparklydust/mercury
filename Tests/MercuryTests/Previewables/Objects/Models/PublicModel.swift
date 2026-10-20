//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import Mercury

/// Exercises a `public` structure so the generated factory keeps the same access level.
@PreviewableFake
public struct PublicModel {
  public let title: String
  public let amount: Int
}
