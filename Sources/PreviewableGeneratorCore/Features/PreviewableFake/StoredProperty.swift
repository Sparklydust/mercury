//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// A stored property a generated fake factory takes an argument for.
struct StoredProperty {

  let name: String
  let type: TypeSyntax
  let isMutable: Bool
}
