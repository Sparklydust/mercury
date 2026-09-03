//
// Copyright © 2026 Swissquote. See LICENSE file for terms. All rights reserved.
//

import Foundation
import PreviewableGeneratorCore

/// The command-line entry point that writes generated Previewable source for a build target.
enum PreviewableGenerator {

    /// Reads the requested Swift sources and writes their generated Previewable declarations.
    /// - Throws: When the output path is missing, a source cannot be read, or output cannot be written.
    static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let outputPath = arguments.first else { throw GeneratorCommandError.missingOutputPath }

        let files = try arguments.dropFirst().map {
            PreviewableSourceFile(path: $0, text: try String(contentsOfFile: $0, encoding: .utf8))
        }
        let generated = try PreviewableSourceGenerator.generate(from: files)
        try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
}

private enum GeneratorCommandError: Error, CustomStringConvertible {
    case missingOutputPath

    var description: String {
        switch self {
        case .missingOutputPath: "error: PreviewableGenerator requires an output path"
        }
    }
}

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
