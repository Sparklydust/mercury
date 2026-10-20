//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import PreviewableGeneratorCore

// Source diagnostics retain their file location; invocation and I/O failures use an unallocated error message.
// - Info: holding an executable target's top-level code, carrying its invocation and nothing else.
do {
  try PreviewableGenerator.run()
} catch let diagnostic as PreviewableDiagnostic {
  FileHandle.standardError.write(Data("\(diagnostic)\n".utf8))
  exit(1)
} catch {
  FileHandle.standardError.write(Data("error: \(error)\n".utf8))
  exit(1)
}
