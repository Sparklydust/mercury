//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

extension String {

  /// The last component of a dot-qualified name, so `Trading.Order` reads as `Order`.
  var simpleName: String {
    split(separator: ".").last.map(String.init) ?? self
  }

  /// Whether the string contains only letters, digits, and underscores, with no leading digit.
  /// Swift keywords are not excluded by this lexical check.
  var isIdentifier: Bool {

    guard let first = unicodeScalars.first,
          CharacterSet.letters.contains(first) || first == "_"
    else { return false }

    return
      unicodeScalars
      .allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
  }
}
