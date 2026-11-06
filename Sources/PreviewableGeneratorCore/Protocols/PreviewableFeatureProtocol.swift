//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import Foundation

/// A feature that validates annotation conflicts and renders derived declarations.
///
/// Conformers report conflicts against the full module and preserve the supplied resolver's allocation state.
protocol PreviewableFeatureProtocol: Sendable {

  /// The annotation this feature generates for.
  static var annotation: PreviewableAnnotation { get }

  /// Returns the first annotation that cannot coexist with an earlier one, or `nil` when the module is consistent.
  /// - Parameter annotations: Every annotated declaration in the module, in source order.
  static func conflict(in annotations: [AnnotatedDeclaration]) -> GenerationFailure?

  /// Generates the declarations one annotated declaration contributes.
  /// - Parameters:
  ///   - annotation: The annotated declaration to generate for.
  ///   - index: The module's declarations, used to read what the annotation refers to.
  ///   - resolver: The default-value resolver, whose accumulated state keeps generated values distinct.
  /// - Throws: `GenerationError` naming what the developer has to change.
  static func generate(
    from annotation: AnnotatedDeclaration,
    index: ModuleIndex,
    resolver: inout DefaultValueResolver
  ) throws -> GeneratedPreviewable
}
