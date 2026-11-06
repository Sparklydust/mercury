//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntax

/// Resolves concrete response defaults while leaving generic associated responses configurable.
enum DoubleResponseDefaultResolver {

  /// Leaves associated-type responses unconfigured when no constructible default exists.
  /// - Parameters:
  ///   - type: The response's rewritten type.
  ///   - resolver: Default construction and the generated generic parameter names.
  /// - Throws: When an unsupported nongeneric type has no default.
  static func resolve(
    for type: TypeSyntax,
    resolver: inout DefaultValueResolver
  ) throws -> String? {
    do { return try resolver.defaultValue(for: type) }
    catch let originalError {
      let canonicalizer = DoubleTypeCanonicalizer(
        index: resolver.index,
        scope: [],
        substitutions: Dictionary(uniqueKeysWithValues: resolver.genericParameters.map { ($0, $0) })
      )
      let resolved = try canonicalizer.resolved(type)

      do { return try resolver.defaultValue(for: resolved) }
      catch {
        guard !resolver.genericParameters.isDisjoint(with: resolved.writtenTypeNames)
        else { throw originalError }

        return nil
      }
    }
  }
}
