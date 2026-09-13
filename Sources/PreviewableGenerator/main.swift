//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import PreviewableGeneratorCore

// The file holding an executable target's top-level code must be named `main.swift`, so this file carries the
// invocation and nothing else.

/// Reports failures in the `path:line:column: error: message` form Xcode renders inline, rather than letting
/// the error escape as an unattributed top-level crash.
do {
    try PreviewableGenerator.run()
} catch let diagnostic as PreviewableDiagnostic {
    FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
