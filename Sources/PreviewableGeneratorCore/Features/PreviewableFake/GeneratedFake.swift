//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// The factory `@PreviewableFake` contributes for one type, in both build configurations.
struct GeneratedFake {

  /// The factory implementation emitted in Debug builds.
  let debug: String
  /// The trapping factory signature emitted outside Debug builds.
  let release: String
}
