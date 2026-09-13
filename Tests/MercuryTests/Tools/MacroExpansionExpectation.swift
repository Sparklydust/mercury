//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// Records macro-expansion differences as Swift Testing issues.
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
