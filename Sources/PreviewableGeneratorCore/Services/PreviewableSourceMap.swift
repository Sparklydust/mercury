//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntax

/// Maps generated declarations and diagnostics back onto the annotations that asked for them.
struct PreviewableSourceMap {

  private let files: [PreviewableSourceFile]
  private let converters: [SourceLocationConverter]

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
  /// The generator cannot check what it never read — an initializer declared in another module above all — so a
  /// mismatch only surfaces once the generated file is compiled. Remapping the location turns "error in a file
  /// buried in DerivedData" into "error on the annotation", which is the only place the developer can fix it.
  ///
  /// Each declaration is wrapped on its own, because they land in different sections of the generated file.
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
