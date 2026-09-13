//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

extension String {

  /// The string with its first character lowercased, preserving the remaining characters.
  var lowercasingFirstCharacter: String {
    guard let first else { return self }
    return first.lowercased() + dropFirst()
  }
}
