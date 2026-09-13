//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import PreviewableGeneratorCore

// The file holding an executable target's top-level code must be named `main.swift`, so this file carries the
// invocation and nothing else.

// Source diagnostics retain their file location; invocation and I/O failures use an unlocated error message.
do {
    try PreviewableGenerator.run()
} catch let diagnostic as PreviewableDiagnostic {
    FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
