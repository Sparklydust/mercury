//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// The declarations one annotated declaration contributes, grouped by where they are emitted.
struct GeneratedPreviewable {

  /// Declarations emitted inside `#if DEBUG`.
  var debug: [String] = []
  /// Declarations emitted inside the matching `#else`.
  var release: [String] = []
  /// Declarations emitted after the `#endif`, because they carry their own availability.
  var unconditional: [String] = []

  /// Appends contributed declarations to each corresponding output section.
  /// - Parameters:
  ///   - accumulated: The output sections to extend.
  ///   - contributed: The declarations to append in their existing order.
  static func += (accumulated: inout Self, contributed: Self) {
    accumulated.debug += contributed.debug
    accumulated.release += contributed.release
    accumulated.unconditional += contributed.unconditional
  }
}
