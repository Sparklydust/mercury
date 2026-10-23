//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises a `public` structure so the generated factory keeps the same access level.
@PreviewableFake
public struct PublicModel {
  public let title: String
  public let amount: Int
}
