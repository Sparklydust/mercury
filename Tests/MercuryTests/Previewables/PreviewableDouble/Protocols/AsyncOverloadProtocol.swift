//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Exercises distinct spies for overloads and nonthrowing behavior for rethrows witnesses.
@PreviewableDouble
protocol AsyncOverloadProtocol: Sendable {

  func load(id: Int) async -> String
  func load(id: String) async -> String
  func perform(_ operation: () throws -> String) async rethrows -> String
}
