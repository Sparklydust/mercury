//
// Copyright © 2026 Mercury contributors. MIT licensed.
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
  public static func require<State: AnyObject & Sendable>(
    for type: Any.Type,
    as state: State.Type
  ) -> State {
    guard let value = states[ObjectIdentifier(type)] as? State
    else { preconditionFailure("Missing Previewable static scope for \(type). Use withStaticStubs.") }

    return value
  }

  /// Runs synchronous work with fresh state while retaining bindings for other double types.
  /// - Parameters:
  ///   - type: The concrete double receiving the state.
  ///   - state: A fresh synchronized reference shared by tasks inheriting this scope.
  ///   - operation: The work whose static calls use the state.
  /// - Throws: Errors thrown by the operation.
  public static func withState<State: AnyObject & Sendable, Result>(
    for type: Any.Type,
    state: State,
    operation: () throws -> Result
  ) rethrows -> Result {
    let bindings = bindings(for: type, state: state)
    return try $states.withValue(bindings, operation: operation)
  }

  /// Runs asynchronous work with fresh state on the caller's isolation.
  /// - Parameters:
  ///   - type: The concrete double receiving the state.
  ///   - state: A fresh synchronized reference shared by inheriting child tasks.
  ///   - operation: The work whose static calls use the state; detached tasks need their own scope.
  /// - Throws: Errors thrown by the operation.
  public nonisolated(nonsending) static func withState<State: AnyObject & Sendable, Result>(
    for type: Any.Type,
    state: State,
    operation: nonisolated(nonsending) () async throws -> Result
  ) async rethrows -> Result {
    let bindings = bindings(for: type, state: state)
    return try await $states.withValue(bindings, operation: operation)
  }
}

private extension PreviewableStaticScope {

  static func bindings<State: AnyObject & Sendable>(
    for type: Any.Type,
    state: State
  ) -> [ObjectIdentifier: any Sendable] {
    var bindings = states
    bindings[ObjectIdentifier(type)] = state
    return bindings
  }
}
