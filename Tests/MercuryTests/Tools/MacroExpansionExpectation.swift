//
// Copyright © 2026 Mercury contributors. MIT licensed.
//

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// Records macro-expansion differences as Swift Testing issues.
/// - Parameters:
///   - originalSource: The annotated Swift input.
///   - expandedSource: The expected source after macro expansion.
///   - diagnostics: Expected compiler diagnostics, in emission order.
///   - macroSpecs: Macro names mapped to their expansion implementations.
///   - fileID: The test file identifier reported for failures.
///   - filePath: The test file path reported for failures.
///   - line: The assertion call's source line.
///   - column: The assertion call's source column.
func expectMacroExpansion(
  _ originalSource: String,
  expandedSource: String,
  diagnostics: [DiagnosticSpec] = [],
  macroSpecs: [String: MacroSpec],
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
    originalSource,
    expandedSource: expandedSource,
    diagnostics: diagnostics,
    macroSpecs: macroSpecs,
    indentationWidth: .spaces(2),
    failureHandler: { failure in
      Issue.record(
        Comment(rawValue: failure.message),
        sourceLocation: .init(
          fileID: failure.location.fileID,
          filePath: failure.location.filePath,
          line: failure.location.line,
          column: failure.location.column
        )
      )
    },
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}
