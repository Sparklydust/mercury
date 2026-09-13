//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

extension String {

  var lowercasingFirstCharacter: String {
    guard let first else { return self }
    return first.lowercased() + dropFirst()
  }
}
