//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

extension String {

  /// The string with its first character lowercased, preserving the remaining characters.
  var lowercasingFirstCharacter: String {
    guard let first else { return self }
    return first.lowercased() + dropFirst()
  }
}
