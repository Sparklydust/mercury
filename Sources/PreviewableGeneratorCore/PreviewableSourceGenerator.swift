//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation

/// Generates derived Swift source for declarations annotated with Previewable macros.
public enum PreviewableSourceGenerator {

  /// Generates the doubles, fake factories, and preview accessors declared by the supplied source files.
  /// - Parameter files: The module's Swift source files, with the paths reported in diagnostics.
  /// - Returns: A compilable Swift source file containing the generated declarations.
  /// - Throws: `PreviewableDiagnostic` naming the declaration that must change.
  public static func generate(
    from files: [PreviewableSourceFile]
  ) throws -> String {
    try PreviewableGenerationPipeline.generate(from: files)
  }

  /// Generates from raw source texts, without file paths.
  /// - Parameter sources: The complete Swift source texts to parse together.
  /// - Returns: A compilable Swift source file containing the generated declarations.
  /// - Throws: `PreviewableDiagnostic` naming the declaration that must change.
  public static func generate(
    from sources: [String]
  ) throws -> String {
    try generate(
      from: sources.enumerated().map {
        PreviewableSourceFile(path: "<source \($0.offset)>", text: $0.element)
      }
    )
  }
}
