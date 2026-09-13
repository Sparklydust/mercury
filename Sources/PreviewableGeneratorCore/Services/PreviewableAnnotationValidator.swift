//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Rejects a module whose annotations cannot be generated, before any declaration is emitted.
///
/// Validating up front is what lets a diagnostic name the declaration to change: once generation starts, the first
/// failure aborts the run and a later, more explanatory conflict would never be reported.
enum PreviewableAnnotationValidator {

  /// - Parameters:
  ///   - index: The module's declarations and annotations.
  ///   - features: The features to ask for conflicts, in the order their diagnostics take precedence.
  ///   - sourceMap: The map that attributes a failure to its annotation.
  /// - Throws: `PreviewableDiagnostic` naming the declaration that has to change.
  static func validate(
    _ index: ModuleIndex,
    features: [any PreviewableFeatureProtocol.Type],
    sourceMap: PreviewableSourceMap
  ) throws {
    try validatePositions(in: index, sourceMap: sourceMap)
    for feature in features {
      guard let failure = feature.conflict(in: index.annotations) else { continue }
      throw sourceMap.diagnostic(failure.message, for: failure.annotation)
    }
  }

  /// Rejects an annotation the generator cannot emit a peer for, whatever the macro asks for.
  private static func validatePositions(in index: ModuleIndex, sourceMap: PreviewableSourceMap) throws {
    for annotation in index.annotations {
      guard case .unsupported(let reason) = annotation.position else { continue }
      throw sourceMap.diagnostic(
                """
                @\(annotation.annotation.rawValue) cannot generate for '\(annotation.name)' declared \
                \(reason) — move the declaration to file scope or nest it directly in a type
                """,
                for: annotation
      )
    }
  }
}
