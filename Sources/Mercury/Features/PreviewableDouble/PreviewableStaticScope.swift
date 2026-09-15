//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Binds synchronized, reference-backed double state to one test execution scope.
@_spi(Generated)
public enum PreviewableStaticScope {

  @TaskLocal private static var states: [ObjectIdentifier: any Sendable] = [:]

  /// Returns the state bound to a concrete double type, or reports a missing scope.
  /// - Parameters:
  ///   - type: The concrete double metatype, including its generic specialization.
  ///   - state: The generated synchronized state type.
  public static func require<State: AnyObject & Sendable>(for type: Any.Type, as state: State.Type) -> State {
    guard let value = states[ObjectIdentifier(type)] as? State else {
      preconditionFailure("Missing Previewable static scope for \(type). Use withStaticStubs.")
    }
    return value
  }

  /// Runs synchronous work with fresh state while retaining bindings for other double types.
  /// - Parameters:
  ///   - type: The concrete double receiving the state.
  ///   - state: A fresh synchronized reference shared by tasks inheriting this scope.
  ///   - operation: The work whose static calls use the state.
  /// - Throws: Errors thrown by the operation.
  public static func withState<State: AnyObject & Sendable, Result>(
    for type: Any.Type, state: State, operation: () throws -> Result
  ) rethrows -> Result {
    var bindings = states
    bindings[ObjectIdentifier(type)] = state
    return try $states.withValue(bindings, operation: operation)
  }

  /// Runs asynchronous work with fresh state on the caller's isolation.
  /// - Parameters:
  ///   - type: The concrete double receiving the state.
  ///   - state: A fresh synchronized reference shared by inheriting child tasks.
  ///   - operation: The work whose static calls use the state; detached tasks need their own scope.
  /// - Throws: Errors thrown by the operation.
  public nonisolated(nonsending) static func withState<State: AnyObject & Sendable, Result>(
    for type: Any.Type, state: State, operation: nonisolated(nonsending) () async throws -> Result
  ) async rethrows -> Result {
    var bindings = states
    bindings[ObjectIdentifier(type)] = state
    return try await $states.withValue(bindings, operation: operation)
  }
}

/// Distinguishes an unconfigured response from a configured optional nil.
@_spi(Generated)
public enum PreviewableValue<Value> {
  case unconfigured
  case configured(Value)

  /// Returns the configured response or identifies the stub that needs configuration.
  /// - Parameter name: The generated stub name reported on failure.
  public func require(_ name: String) -> Value {
    guard case .configured(let value) = self else {
      preconditionFailure("Missing Previewable response for \(name)")
    }
    return value
  }
}

extension PreviewableValue: Sendable where Value: Sendable {}
