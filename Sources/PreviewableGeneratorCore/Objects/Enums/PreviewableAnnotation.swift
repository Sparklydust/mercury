//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// The Previewable macro attached to a declaration.
enum PreviewableAnnotation: String {

  /// Requests a conforming double and shared preview accessor for a protocol.
  case double = "PreviewableDouble"
  /// Requests a factory with generated default arguments.
  case fake = "PreviewableFake"
}
