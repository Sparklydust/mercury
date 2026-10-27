//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises the same deferral in a double, where the requirement writes the stub type.
@PreviewableDouble
protocol SynthesizedServiceProtocol {
  var zone: TimeZone { get }
  func load() -> Range<Int>
}
