//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import PreviewableGeneratorCore

/// Returns the diagnostic raised while generating the supplied file, or `nil` when generation succeeds.
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

/// Returns the diagnostic message raised while generating the supplied source, or `nil` when generation succeeds.
func generatorDiagnosticMessage(for source: String) -> String? {
    generatorDiagnostic(for: PreviewableSourceFile(path: "Source.swift", text: source))?.message
}
