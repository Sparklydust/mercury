//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises a conformance supplying the default of a type declared outside the module.
extension TimeZone: PreviewableSynthesizable {

  /// The value used when the caller supplies no override.
  public static var previewableDefault: TimeZone { .gmt }
}
