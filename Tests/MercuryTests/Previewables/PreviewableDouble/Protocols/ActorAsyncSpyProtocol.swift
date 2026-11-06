//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Exercises custom-actor method and getter controls without requiring the main actor.
@RecordingActor
@PreviewableDouble
protocol ActorAsyncSpyProtocol {

  func load() async -> Session
  var payload: Session { get async }
  static func count() async -> Int
}
