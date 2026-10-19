//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Stores independently configured generic responses by their concrete return type.
///
/// Concurrent reads and updates are synchronized. An optional `nil` is a configured response, not removal.
/// Concurrent configuration order is unspecified. Configure before spawning child tasks for deterministic responses.
public final class PreviewableResponses: @unchecked Sendable {

  private let lock = NSLock()
  private var values: [ObjectIdentifier: any Sendable] = [:]

  /// Creates an empty response store.
  public init() {}

  /// Configures the response returned for a concrete type.
  /// - Parameters:
  ///   - value: The response, including an explicitly typed optional `nil`.
  ///   - type: The return type requested by the generic method.
  public func set<Value: Sendable>(_ value: Value, for type: Value.Type) {
    lock.withLock { values[ObjectIdentifier(type)] = Response(value: value) }
  }

  /// Removes the response for a concrete type.
  /// - Parameter type: The return type whose response is removed.
  public func remove<Value>(for type: Value.Type) {
    _ = lock.withLock { values.removeValue(forKey: ObjectIdentifier(type)) }
  }

  /// Returns a configured response or stops at an unconfigured generic invocation.
  /// - Parameters:
  ///   - type: The concrete return type.
  ///   - method: The generated method name included in a failure diagnostic.
  @_spi(Generated)
  public func require<Value: Sendable>(_ type: Value.Type, method: String) -> Value {
    let response = lock.withLock { values[ObjectIdentifier(type)] as? Response<Value> }
    guard let response else {
      preconditionFailure("Missing Previewable response for \(method) returning \(String(reflecting: type))")
    }
    return response.value
  }
}

private extension PreviewableResponses {

  struct Response<Value: Sendable>: Sendable {
    let value: Value
  }
}
