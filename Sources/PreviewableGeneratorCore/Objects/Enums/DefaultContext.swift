//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Whether defaults are being generated for a test double or for a fake factory.
enum DefaultContext {

  /// Doubles favour neutral zero values that a test can overwrite.
  case double
  /// Fakes favour distinct, recognisable values suitable for previews.
  case fake
}
