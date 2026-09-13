//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import PreviewableGeneratorCore

/// The command-line entry point that writes generated Previewable source for a build target.
enum PreviewableGenerator {

  /// Reads the requested Swift sources and writes their generated Previewable declarations.
  /// The first command-line argument is the output path; remaining arguments are input paths.
  /// - Throws: For a missing output path, invalid source declarations, or file read and write failures.
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
