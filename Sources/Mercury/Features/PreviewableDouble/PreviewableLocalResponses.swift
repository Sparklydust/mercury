//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

/// Stores generic responses for doubles that remain in one isolation domain.
///
/// Values may be non-Sendable. Keep this store with its owning double or global actor.
public final class PreviewableLocalResponses {

  private var values: [ObjectIdentifier: Any] = [:]

  /// Creates an empty response store.
  public init() {}

  /// Configures a response, including an explicitly typed optional nil.
  /// - Parameters:
  ///   - value: The response returned by the generic requirement.
  ///   - type: The concrete return type used to identify the response.
  public func set<Value>(_ value: Value, for type: Value.Type) {
    values[ObjectIdentifier(type)] = Response(value: value)
  }

  /// Removes the response for a concrete type.
  /// - Parameter type: The return type whose response is removed.
  public func remove<Value>(for type: Value.Type) {
    values.removeValue(forKey: ObjectIdentifier(type))
  }

  /// Returns the configured response or stops at an unconfigured invocation.
  /// - Parameters:
  ///   - type: The concrete return type requested by the requirement.
  ///   - method: The generated method name included in a failure diagnostic.
  @_spi(Generated)
  public func require<Value>(_ type: Value.Type, method: String) -> Value {
    guard let response = values[ObjectIdentifier(type)] as? Response<Value> else {
      preconditionFailure("Missing Previewable response for \(method) returning \(String(reflecting: type))")
    }
    return response.value
  }
}

private extension PreviewableLocalResponses {

  struct Response<Value> {
    let value: Value
  }
}
