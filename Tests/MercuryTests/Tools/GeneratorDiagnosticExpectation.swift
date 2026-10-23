//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import PreviewableGeneratorCore

/// Returns a source diagnostic, or `nil` when generation succeeds or throws another error type.
/// - Parameter file: The source file to generate in isolation.
func generatorDiagnostic(for file: PreviewableSourceFile) -> PreviewableDiagnostic? {
  do {
    _ = try PreviewableSourceGenerator.generate(from: [file])
    return nil
  } catch let diagnostic as PreviewableDiagnostic {
    return diagnostic
  } catch {
    return nil
  }
}

/// Returns the source diagnostic message, or `nil` if no source diagnostic is thrown.
/// - Parameter source: The Swift text to generate using a synthetic file path.
func generatorDiagnosticMessage(for source: String) -> String? {
  generatorDiagnostic(for: PreviewableSourceFile(path: "Source.swift", text: source))?.message
}
