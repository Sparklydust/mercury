//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises fake defaults the generator defers to `PreviewableSynthesizable` because it cannot read the declaration.
@PreviewableFake
struct SynthesizedModel {
  let zone: TimeZone
  let span: Range<Int>
  let interval: Range<Double>
}
