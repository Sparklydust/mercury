//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftParser
import SwiftSyntax

/// Renders subscript witnesses with distinct accessor recordings and typed response-resolution boundaries.
enum DoubleSubscriptBuilder {

  /// Renders a subscript, preserving every argument for future argument-based response policies.
  /// - Parameters:
  ///   - requirement: The canonical subscript requirement and allocated stub name.
  ///   - access: The double's effective access prefix.
  ///   - isolated: Whether the protocol has global-actor isolation.
  ///   - sendable: Whether unisolated indices and responses must conform to `Sendable`.
  ///   - resolver: The default construction context.
  /// - Throws: For unsupported argument forms or unavailable response defaults.
  static func generate(
    _ requirement: DoubleRequirement,
    access: String,
    isolated: Bool,
    sendable: Bool,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedMethod {
    let context = DoubleSubscriptContext(
      requirement: requirement,
      access: access,
      isolated: isolated,
      sendable: sendable
    )
    let getter = try context.getter(resolver: &resolver)
    let accessors = try context.accessors(getter: getter, resolver: &resolver)

    return context.render(stubs: getter.stubs, accessors: accessors)
  }
}
