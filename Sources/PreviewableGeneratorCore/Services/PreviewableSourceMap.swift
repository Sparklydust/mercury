//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Maps generated declarations and diagnostics back onto the annotations that asked for them.
struct PreviewableSourceMap {

  private let files: [PreviewableSourceFile]
  private let converters: [SourceLocationConverter]

  /// Creates source-location converters for the supplied files.
  /// - Parameters:
  ///   - files: The module's source files, with the paths reported in diagnostics.
  ///   - trees: Their parsed syntax, in the same order — the two stay index-parallel.
  init(files: [PreviewableSourceFile], trees: [SourceFileSyntax]) {
    self.files = files
    converters = zip(files, trees).map {
      SourceLocationConverter(fileName: $0.path, tree: $1)
    }
  }

  /// Wraps every generated declaration so the compiler reports its diagnostics on the annotation that asked for it.
  ///
  /// Each declaration receives an independent source-location directive because output sections differ.
  /// Compiler diagnostics retain offsets within the generated declaration after the mapped starting line.
  /// - Parameters:
  ///   - generated: The declarations grouped by build configuration.
  ///   - annotation: The source annotation to use as the compiler location.
  func attributed(
    _ generated: GeneratedPreviewable,
    to annotation: AnnotatedDeclaration
  ) -> GeneratedPreviewable {
    let location = directive(for: annotation)
    return GeneratedPreviewable(
      debug: generated.debug.map { attributed($0, to: location) },
      release: generated.release.map { attributed($0, to: location) },
      unconditional: generated.unconditional.map { attributed($0, to: location) }
    )
  }

  /// Returns the failure Xcode renders inline on the annotated declaration.
  /// - Parameters:
  ///   - message: The validation failure to report.
  ///   - annotation: The declaration whose location identifies the failure.
  func diagnostic(_ message: String, for annotation: AnnotatedDeclaration) -> PreviewableDiagnostic {
    let converter = converters[annotation.fileIndex]
    let location = converter.location(for: annotation.absolutePosition)
    return PreviewableDiagnostic(
      path: files[annotation.fileIndex].path,
      line: location.line,
      column: location.column,
      message: message
    )
  }

  /// Returns the `#sourceLocation` directive that maps generated source back onto an annotation.
  private func directive(for annotation: AnnotatedDeclaration) -> String {
    let path = files[annotation.fileIndex].path
    let line = converters[annotation.fileIndex].location(for: annotation.absolutePosition).line
    return "#sourceLocation(file: \(String(reflecting: path)), line: \(line))"
  }

  /// Closes the remapping after the declaration, so it never leaks onto the next one.
  ///
  /// The directive sets the line of what follows it and the compiler counts up from there, so a diagnostic raised
  /// deeper in the generated declaration is reported a few lines below the annotation, past the end of the file
  /// for a short one. The file and the message stay correct, which is what makes the error actionable.
  private func attributed(_ source: String, to location: String) -> String {
        """
        \(location)
        \(source)
        #sourceLocation()
        """
  }
}
