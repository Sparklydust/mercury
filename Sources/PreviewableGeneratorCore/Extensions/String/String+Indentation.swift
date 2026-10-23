//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

extension String {

  /// Returns the source indented by the requested spaces, leaving blank lines empty.
  func indented(by spaces: Int) -> String {
    let prefix = String(repeating: " ", count: spaces)

    return split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.isEmpty ? String() : prefix + $0 }
      .joined(separator: "\n")
  }
}
