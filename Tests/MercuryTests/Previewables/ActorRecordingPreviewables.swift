//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Mercury

/// Owns the custom-actor argument records used by concurrency tests.
@globalActor
actor RecordingActor {
  static let shared = RecordingActor()
}

/// A mutable argument that must remain on the actor that records it.
final class RecordedPayload {
  var value = 0
}

/// Exercises independent recording domains within one double.
@PreviewableDouble
protocol ActorRecordingProtocol: Sendable {
  @MainActor func store(_ payload: RecordedPayload)
  @RecordingActor func cache(_ payload: RecordedPayload)
  func load(id: Int) -> String
}

/// Exercises nonisolated requirements on an otherwise isolated double.
@MainActor
@PreviewableDouble
protocol MixedIsolationProtocol {
  nonisolated var count: Int { get set }
  nonisolated func load(id: Int) -> String
  func store(_ payload: RecordedPayload)
}
