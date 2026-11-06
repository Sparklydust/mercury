//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftParser
import SwiftSyntax

/// A stored property a generated fake factory takes an argument for.
struct StoredProperty {

  /// The property name used as the initializer argument label.
  let name: String
  /// The type used for the factory parameter and default resolution.
  let type: TypeSyntax
  /// Whether the original declaration permits assignment after initialization.
  let isMutable: Bool

  /// The property name with Swift keywords escaped for labels and local references.
  var escapedName: String {
    guard case .keyword = Parser.parse(source: name).firstToken(viewMode: .sourceAccurate)?.tokenKind
    else { return name }
    return "`\(name)`"
  }
}
