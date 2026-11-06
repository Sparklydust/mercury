//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises scalar, date, identifier and URL defaults on a structure.
@PreviewableFake
struct Account {
  let identifier: UUID
  let owner: String
  let label: String
  let balance: Double
  let openedAt: Date
  let closedAt: Date
  let statement: URL
  let isActive: Bool
}
