//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

extension UUID: PreviewableSynthesizable {

  /// A newly generated UUID on each read.
  public static var previewableDefault: UUID { .init() }
}
