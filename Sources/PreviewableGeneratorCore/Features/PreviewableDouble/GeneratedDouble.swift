//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// The two declarations `@PreviewableDouble` contributes for one protocol.
struct GeneratedDouble {

  /// The conforming double declaration emitted in Debug builds.
  let declaration: String
  /// The shared accessor with separate Debug and non-Debug implementations.
  let previewConfiguration: String
  /// The type and optional accessor names reserved at file scope.
  let globalNames: [String]
}
