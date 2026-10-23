//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation
import Mercury

/// Exercises concurrent calls and responses indexed by generic return type.
@PreviewableDouble
protocol ConcurrentServiceProtocol: Sendable {
  func load(key: Int) async throws -> String
  func make<Value: Codable & Sendable>(_ type: Value.Type) async throws -> Value
}
