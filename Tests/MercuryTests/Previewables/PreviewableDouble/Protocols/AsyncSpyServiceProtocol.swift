//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Mercury

/// Exercises independent async controls across methods, properties, generics, and static scopes.
@PreviewableDouble
protocol AsyncSpyServiceProtocol: Sendable {

  func load() async throws(ScopedFailure) -> String
  func refresh() async
  func make<Value: Sendable>(_ type: Value.Type) async throws -> Value
  var status: String { get async throws(ScopedFailure) }
  static func version() async -> Int
  static var revision: Int { get async }
}
