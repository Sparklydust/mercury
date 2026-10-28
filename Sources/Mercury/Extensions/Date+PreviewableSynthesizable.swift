//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

extension Date: PreviewableSynthesizable {

  /// The Unix epoch, `1970-01-01T00:00:00Z`.
  public static var previewableDefault: Date { .init(timeIntervalSince1970: 0) }
}
