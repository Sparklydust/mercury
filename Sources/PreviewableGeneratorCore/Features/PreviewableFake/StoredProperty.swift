//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// A stored property a generated fake factory takes an argument for.
struct StoredProperty {

  /// The property name used as the initializer argument label.
  let name: String
  /// The type used for the factory parameter and default resolution.
  let type: TypeSyntax
  /// Whether the original declaration permits assignment after initialization.
  let isMutable: Bool
}
