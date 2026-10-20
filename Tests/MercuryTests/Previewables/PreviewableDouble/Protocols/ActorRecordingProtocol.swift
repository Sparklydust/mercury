//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// Exercises independent recording domains within one double.
@PreviewableDouble
protocol ActorRecordingProtocol: Sendable {
  @MainActor func store(_ payload: RecordedPayload)
  @RecordingActor func cache(_ payload: RecordedPayload)
  func load(id: Int) -> String
}
