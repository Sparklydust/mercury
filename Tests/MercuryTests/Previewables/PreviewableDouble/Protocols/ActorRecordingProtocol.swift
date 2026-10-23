//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Exercises independent recording domains within one double.
@PreviewableDouble
protocol ActorRecordingProtocol: Sendable {
  @MainActor func store(_ payload: RecordedPayload)
  @RecordingActor func cache(_ payload: RecordedPayload)
  func load(id: Int) -> String
}
