//
// Copyright © 2026 Roland Lariotte. See LICENSE file for terms. All rights reserved.
//

import Foundation
import PreviewableGeneratorCore

/// The command-line entry point that writes generated Previewable source for a build target.
enum PreviewableGenerator {

  /// Reads the requested Swift sources and writes their generated Previewable declarations.
  /// The first argument is the output path, followed by input paths or `--input-file-list` and a JSON path array.
  /// - Throws: For a missing output path, invalid source declarations, or file read and write failures.
  static func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let outputPath = arguments.first else { throw GeneratorCommandError.missingOutputPath }

    let inputs = Array(arguments.dropFirst())
    let paths: [String]
    if inputs.first == "--input-file-list" {
      guard inputs.count == 2 else { throw GeneratorCommandError.missingInputFileList }
      paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: inputs[1])))
    } else {
      paths = inputs
    }
    let files = try paths.sorted().map {
      PreviewableSourceFile(path: $0, text: try String(contentsOfFile: $0, encoding: .utf8))
    }
    let cacheURL = URL(fileURLWithPath: outputPath + ".cache.json")
    let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    let inputDigest = try PreviewableGenerationCache.fingerprint(files: files, executable: executable)
    let previous = try? String(contentsOfFile: outputPath, encoding: .utf8)
    if let previous, let data = try? Data(contentsOf: cacheURL),
      let cache = try? JSONDecoder().decode(PreviewableGenerationCache.self, from: data),
      cache.inputs == inputDigest, cache.output == PreviewableGenerationCache.fingerprint(previous)
    {
      return
    }
    let generated = try PreviewableSourceGenerator.generate(from: files)
    // Preserve the modification time so an unchanged declaration does not invalidate consumer compilation.
    if previous != generated {
      try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
    let cache = PreviewableGenerationCache(inputs: inputDigest, output: PreviewableGenerationCache.fingerprint(generated))
    try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
  }
}
