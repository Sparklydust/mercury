//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises a conditional conformance specialized by the generic arguments of a type declared outside the module.
extension Range: PreviewableSynthesizable where Bound: PreviewableSynthesizable {

  /// The empty range built from the bound's own default.
  public static var previewableDefault: Range<Bound> { Bound.previewableDefault..<Bound.previewableDefault }
}
